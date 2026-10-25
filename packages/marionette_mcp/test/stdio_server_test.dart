@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/test_process.dart';

/// End-to-end tests for the stdio MCP server.
///
/// These spawn the real entrypoint ([bin/marionette_mcp.dart]) and drive it
/// over stdin/stdout, so they exercise the actual transport wiring rather than
/// an in-process stub.
void main() {
  // Relative to the package root, which is the working directory under
  // `dart test`.
  const entrypoint = 'bin/marionette_mcp.dart';

  Future<Process> startServer() {
    return Process.start(
      Platform.resolvedExecutable,
      ['run', entrypoint, '--log-level', 'SEVERE'],
    );
  }

  group('stdio server', () {
    test(
      'completes the initialize handshake for a Copilot-style request',
      () async {
        final process = await startServer();
        addTearDown(process.kill);
        // Drain stderr so the pipe never fills and blocks the child.
        unawaited(process.stderr.drain<void>());

        // GitHub Copilot advertises `tasks.list` / `tasks.cancel` as objects
        // (`{}`) instead of booleans. This previously needed a custom transport
        // to rewrite; mcp_dart 2.1.0 parses it natively. This is the regression
        // guard for that behavior.
        const initialize = {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-06-18',
            'capabilities': {
              'tasks': {
                'list': <String, dynamic>{},
                'cancel': <String, dynamic>{}
              },
            },
            'clientInfo': {'name': 'copilot', 'version': '1.0.0'},
          },
        };

        final responses = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.trim().isNotEmpty)
            .map((line) => jsonDecode(line) as Map<String, dynamic>);

        process.stdin.writeln(jsonEncode(initialize));
        await process.stdin.flush();

        final response = await responses.firstWhere((msg) => msg['id'] == 1);

        expect(
          response['error'],
          isNull,
          reason: 'the handshake must not produce a JSON-RPC error',
        );
        expect(response['result'], isA<Map>());
        final result = response['result'] as Map;
        expect(result['serverInfo'], isA<Map>());
        expect(result['capabilities'], isA<Map>());
      },
    );

    for (final signal in [false, if (!Platform.isWindows) true]) {
      test(
        'exits with code 0 while connected on '
        '${signal ? 'SIGTERM' : 'stdin EOF'}',
        () async {
          final app = await TestProcess.start([
            '--enable-vm-service=0',
            '--disable-service-auth-codes',
            'test/fixtures/vm_service_app.dart',
          ]);
          addTearDown(app.dispose);
          final uri = await app.vmServiceUri();

          final server = await TestProcess.start([
            'run',
            entrypoint,
            '--log-level',
            'SEVERE',
          ]);
          addTearDown(server.dispose);
          server.send({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': {
              'protocolVersion': '2025-06-18',
              'capabilities': <String, Object?>{},
              'clientInfo': {'name': 'shutdown-test', 'version': '1.0.0'},
            },
          });
          final initialized = await server.response(1);
          expect(initialized['error'], isNull);
          expect(initialized['result'], isA<Map>());
          server.send({
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          });
          server.send({
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'tools/call',
            'params': {
              'name': 'connect',
              'arguments': {'uri': uri},
            },
          });
          final connected = await server.response(2);
          expect(connected['error'], isNull);
          expect(connected['result'], isA<Map>());
          final result = connected['result'] as Map;
          expect(result['isError'], isNot(true), reason: '$connected');

          // Keep the VM connection alive: shutdown must dispose it without
          // requiring an explicit disconnect tool call from the client.
          if (signal) {
            expect(server.process.kill(ProcessSignal.sigterm), isTrue);
          } else {
            await server.process.stdin.close();
          }
          expect(
            await server.exitCodeWithin(const Duration(seconds: 10)),
            0,
            reason: server.errors.toString(),
          );
        },
      );
    }

    for (final signal in [false, if (!Platform.isWindows) true]) {
      test(
        'exits with code 0 during a pending VM WebSocket upgrade on '
        '${signal ? 'SIGTERM' : 'stdin EOF'}',
        () async {
          final listener =
              await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final accepted = Completer<HttpRequest>();
          final requests = listener.listen((request) {
            if (!accepted.isCompleted) accepted.complete(request);
          });
          addTearDown(() async {
            await listener.close(force: true);
            await requests.cancel();
          });
          final server = await TestProcess.start([
            'run',
            entrypoint,
            '--log-level',
            'SEVERE',
          ]);
          addTearDown(server.dispose);
          server.send({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': {
              'protocolVersion': '2025-06-18',
              'capabilities': <String, Object?>{},
              'clientInfo': {'name': 'pending-shutdown-test', 'version': '1'},
            },
          });
          final initialized = await server.response(1);
          expect(initialized['error'], isNull);
          server.send({
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          });
          server.send({
            'jsonrpc': '2.0',
            'id': 2,
            'method': 'tools/call',
            'params': {
              'name': 'connect',
              'arguments': {'uri': 'ws://127.0.0.1:${listener.port}/ws'},
            },
          });
          final request = await accepted.future.timeout(
            const Duration(seconds: 15),
          );
          expect(WebSocketTransformer.isUpgradeRequest(request), isTrue);

          // Leave the HTTP upgrade unanswered until after process exit. Merely
          // closing a late successful WebSocket does not release a still-open
          // HttpClient request, which would otherwise keep the process alive.
          if (signal) {
            expect(server.process.kill(ProcessSignal.sigterm), isTrue);
          } else {
            await server.process.stdin.close();
          }
          expect(
            await server.exitCodeWithin(const Duration(seconds: 10)),
            0,
            reason: server.errors.toString(),
          );
        },
      );
    }

    test('exits with code 0 when stdin reaches EOF', () async {
      final process = await startServer();
      addTearDown(process.kill);

      // Drain output so the pipes don't fill up while we wait.
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());

      // Close stdin → EOF. The server should shut down rather than hang until
      // SIGINT/SIGTERM (the orphaned-process bug, #84).
      await process.stdin.close();

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          process.kill();
          throw TimeoutException(
            'Server did not exit within 15s of stdin EOF',
          );
        },
      );

      expect(exitCode, equals(0));
    });
  });
}
