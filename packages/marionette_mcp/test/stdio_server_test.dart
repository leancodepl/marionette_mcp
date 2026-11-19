@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// End-to-end tests for the stdio MCP server.
///
/// These spawn the real entrypoint ([bin/marionette_mcp.dart]) and drive it
/// over stdin/stdout, so they exercise the actual transport wiring rather than
/// an in-process stub.
void main() {
  // Relative to the package root, which is the working directory under
  // `dart test`.
  const entrypoint = 'bin/marionette_mcp.dart';

  Future<Process> startServer([List<String> extraArgs = const []]) {
    return Process.start(
      Platform.resolvedExecutable,
      ['run', entrypoint, '--log-level', 'SEVERE', ...extraArgs],
    );
  }

  /// The JSON-RPC messages the server writes to stdout, one per line.
  Stream<Map<String, dynamic>> jsonLines(Process process) {
    return process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>);
  }

  /// Starts the server with [args], completes the handshake and returns the
  /// instructions it sends and the tools `tools/list` reports.
  Future<({String instructions, List<Map<String, dynamic>> tools})>
      startAndHandshake(List<String> args) async {
    final process = await startServer(args);
    addTearDown(process.kill);
    unawaited(process.stderr.drain<void>());
    final responses = StreamIterator(jsonLines(process));
    Future<Map<String, dynamic>> result(int id) async {
      while (await responses.moveNext()) {
        if (responses.current['id'] == id) {
          return responses.current['result'] as Map<String, dynamic>;
        }
      }
      throw StateError('no response $id');
    }

    process.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'test', 'version': '1.0.0'},
      },
    }));
    final initialized = await result(1);
    process.stdin
      ..writeln(jsonEncode(
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      ))
      ..writeln(
          jsonEncode({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'}));
    final listed = await result(2);
    await responses.cancel();
    return (
      instructions: initialized['instructions'] as String,
      tools: (listed['tools'] as List).cast<Map<String, dynamic>>(),
    );
  }

  Map<String, dynamic> tool(List<Map<String, dynamic>> tools, String name) =>
      tools.singleWhere((tool) => tool['name'] == name);

  Iterable<Map<String, dynamic>> nativeTools(
    List<Map<String, dynamic>> tools,
  ) =>
      tools.where((tool) => (tool['name'] as String).startsWith('native_'));

  group('native lane', () {
    test('is on by default: native tools and instructions', () async {
      final handshake = await startAndHandshake(const []);

      expect(nativeTools(handshake.tools), hasLength(12));
      expect(handshake.instructions, contains('Native lane'));
      expect(
        tool(handshake.tools, 'get_interactive_elements')['description'],
        contains('native_get_elements'),
      );
    });

    test('--no-native leaves out every native tool and text', () async {
      final handshake = await startAndHandshake(const ['--no-native']);

      expect(nativeTools(handshake.tools), isEmpty);
      expect(
        handshake.instructions,
        allOf(isNot(contains('Native lane')), isNot(contains('native_'))),
      );
      expect(
        tool(handshake.tools, 'get_interactive_elements')['description'],
        isNot(contains('native_')),
      );
    });
  });

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

        final responses = jsonLines(process);

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
