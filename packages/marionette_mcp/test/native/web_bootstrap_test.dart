import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/web_bootstrap.dart';
import 'package:test/test.dart';

void main() {
  group('WebBootstrap', () {
    test('attach mode health-checks existingServerUrl', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/status') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'value': {'ready': true},
          }));
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });

      final bootstrap = WebBootstrap(
        existingServerUrl: 'http://127.0.0.1:${server.port}',
        processRunner: (exe, args) async =>
            throw StateError('should not spawn'),
      );
      addTearDown(bootstrap.dispose);

      final uri = await bootstrap.ensureServerReady();
      expect(uri.port, server.port);
    });

    test('throws when chromedriver missing from PATH', () async {
      final bootstrap = WebBootstrap(
        chromeDriverPath: 'definitely-not-chromedriver-xyz',
        processRunner: (exe, args) async {
          return ProcessResult(1, 1, '', 'not found');
        },
      );
      addTearDown(bootstrap.dispose);

      expect(
        () => bootstrap.ensureServerReady(),
        throwsA(
          isA<WebBootstrapException>().having(
            (e) => e.failure,
            'failure',
            WebBootstrapFailure.chromeDriverMissing,
          ),
        ),
      );
    });

    test('starts chromedriver and waits for /status', () async {
      final statusServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => statusServer.close(force: true));
      final port = statusServer.port;
      statusServer.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'value': {'ready': true},
        }));
        await request.response.close();
      });

      final fakeBin = File(
        '${Directory.systemTemp.createTempSync('marionette_cd_').path}'
        '/chromedriver',
      )..writeAsStringSync('#!/bin/sh\n');
      addTearDown(() {
        fakeBin.parent.deleteSync(recursive: true);
      });

      List<String>? startedArgs;
      final bootstrap = WebBootstrap(
        chromeDriverPath: fakeBin.path,
        localPort: port,
        processRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
        processStarter: (exe, args) async {
          startedArgs = args;
          return Process.start(
            Platform.isWindows ? 'cmd' : 'sleep',
            Platform.isWindows ? ['/c', 'timeout', '30'] : ['30'],
          );
        },
      );
      addTearDown(bootstrap.dispose);

      final uri = await bootstrap.ensureServerReady();
      expect(uri.port, port);
      expect(startedArgs, contains('--port=$port'));
    });
  });
}
