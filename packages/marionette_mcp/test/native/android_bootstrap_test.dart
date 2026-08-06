import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidBootstrap', () {
    late Directory cacheDir;
    late HttpServer statusServer;
    late int localPort;
    late List<(String, List<String>)> adbCalls;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('marionette_uia2_');
      adbCalls = [];
      statusServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      localPort = statusServer.port;
      statusServer.listen((request) async {
        if (request.uri.path == '/status') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'value': {'ready': true},
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await statusServer.close(force: true);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    });

    ProcessResult ok([String stdout = '']) => ProcessResult(0, 0, stdout, '');

    Future<ProcessResult> recordingRunner(
      String executable,
      List<String> arguments, {
      ProcessResult Function(List<String> args)? onCall,
    }) async {
      expect(executable, 'adb');
      adbCalls.add((executable, List<String>.from(arguments)));
      if (onCall != null) return onCall(arguments);
      return ok('device');
    }

    List<String> stripSerial(List<String> args) {
      if (args.length >= 2 && args[0] == '-s') {
        return args.sublist(2);
      }
      return args;
    }

    test('missing adb throws AndroidBootstrapException(adbMissing)', () async {
      final bootstrap = AndroidBootstrap(
        processRunner: (executable, arguments) async {
          throw ProcessException(
            executable,
            arguments,
            'No such file or directory',
            2,
          );
        },
        downloader: (_) async => [1],
        cacheDir: cacheDir,
        localPort: localPort,
      );

      expect(
        () => bootstrap.ensureServerReady(),
        throwsA(
          isA<AndroidBootstrapException>()
              .having(
                (e) => e.failure,
                'failure',
                AndroidBootstrapFailure.adbMissing,
              )
              .having((e) => e.message, 'message', contains('adb')),
        ),
      );
    });

    test('device not online throws deviceUnavailable', () async {
      final bootstrap = AndroidBootstrap(
        processRunner: (executable, arguments) async {
          adbCalls.add((executable, List<String>.from(arguments)));
          final cmd = stripSerial(arguments);
          if (cmd.first == 'version') return ok('1.0.41');
          if (cmd.first == 'get-state') {
            return ProcessResult(0, 1, 'offline', 'error: device offline');
          }
          return ok();
        },
        downloader: (_) async => [1],
        cacheDir: cacheDir,
        localPort: localPort,
      );

      expect(
        () => bootstrap.ensureServerReady(),
        throwsA(
          isA<AndroidBootstrapException>().having(
            (e) => e.failure,
            'failure',
            AndroidBootstrapFailure.deviceUnavailable,
          ),
        ),
      );
    });

    test(
      'ensureServerReady installs, instruments, forwards, and becomes healthy',
      () async {
        final downloadedUrls = <Uri>[];
        final bootstrap = AndroidBootstrap(
          serial: 'emulator-5554',
          processRunner: (executable, arguments) => recordingRunner(
            executable,
            arguments,
            onCall: (args) {
              final cmd = stripSerial(args);
              if (cmd.first == 'version') return ok('1.0.41');
              if (cmd.first == 'get-state') return ok('device');
              if (cmd.first == 'install') return ok('Success');
              if (cmd.length >= 3 && cmd[0] == 'shell' && cmd[1] == 'am' && cmd[2] == 'instrument') {
                return ok();
              }
              if (cmd.first == 'forward') return ok();
              if (cmd.length >= 3 && cmd[0] == 'shell' && cmd[1] == 'am' && cmd[2] == 'force-stop') {
                return ok();
              }
              return ok();
            },
          ),
          downloader: (url) async {
            downloadedUrls.add(url);
            return [0x50, 0x4B, 0x03, 0x04]; // minimal zip/apk-ish bytes
          },
          cacheDir: cacheDir,
          localPort: localPort,
        );

        final uri = await bootstrap.ensureServerReady();
        expect(uri.port, localPort);
        expect(uri.host, '127.0.0.1');

        expect(downloadedUrls, hasLength(2));
        expect(
          downloadedUrls.every(
            (u) => u.path.contains('appium-uiautomator2-server'),
          ),
          isTrue,
        );

        final commandSequences = adbCalls
            .map((call) => stripSerial(call.$2))
            .where((cmd) =>
                cmd.first == 'install' ||
                cmd.first == 'forward' ||
                (cmd.length >= 3 && cmd[0] == 'shell' && cmd[2] == 'instrument'))
            .toList();

        expect(commandSequences[0].take(3).toList(), ['install', '-r', '-t']);
        expect(commandSequences[1].take(3).toList(), ['install', '-r', '-t']);
        expect(
          commandSequences[2],
          [
            'shell',
            'am',
            'instrument',
            '-e',
            'disableAnalytics',
            'true',
            'io.appium.uiautomator2.server.test/'
                'androidx.test.runner.AndroidJUnitRunner',
          ],
        );
        expect(commandSequences[3], ['forward', 'tcp:$localPort', 'tcp:6790']);

        // Serial is threaded into adb invocations.
        expect(
          adbCalls.every((call) => call.$2.length >= 2 && call.$2[0] == '-s' && call.$2[1] == 'emulator-5554'),
          isTrue,
        );

        await bootstrap.dispose();
      },
    );

    test('install failure throws AndroidBootstrapException(install)', () async {
      final bootstrap = AndroidBootstrap(
        processRunner: (executable, arguments) async {
          final cmd = stripSerial(arguments);
          if (cmd.first == 'version') return ok('1.0.41');
          if (cmd.first == 'get-state') return ok('device');
          if (cmd.first == 'install') {
            return ProcessResult(0, 1, '', 'Failure [INSTALL_FAILED]');
          }
          return ok();
        },
        downloader: (_) async => [1, 2, 3],
        cacheDir: cacheDir,
        localPort: localPort,
      );

      expect(
        () => bootstrap.ensureServerReady(),
        throwsA(
          isA<AndroidBootstrapException>()
              .having(
                (e) => e.failure,
                'failure',
                AndroidBootstrapFailure.install,
              )
              .having(
                (e) => e.message,
                'message',
                contains('INSTALL_FAILED'),
              ),
        ),
      );
    });

    test('empty download throws download failure', () async {
      final bootstrap = AndroidBootstrap(
        processRunner: (executable, arguments) async {
          final cmd = stripSerial(arguments);
          if (cmd.first == 'version') return ok('1.0.41');
          if (cmd.first == 'get-state') return ok('device');
          return ok();
        },
        downloader: (_) async => <int>[],
        cacheDir: cacheDir,
        localPort: localPort,
      );

      expect(
        () => bootstrap.ensureServerReady(),
        throwsA(
          isA<AndroidBootstrapException>().having(
            (e) => e.failure,
            'failure',
            AndroidBootstrapFailure.download,
          ),
        ),
      );
    });
  });
}
