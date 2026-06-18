import 'dart:async';

import 'package:marionette_mcp/src/compat/copilot_stdio_server_transport.dart';
import 'package:test/test.dart';

void main() {
  group('CopilotCompatStdioServerTransport', () {
    test('done completes (and onclose fires) when stdin reaches EOF', () async {
      final stdin = StreamController<List<int>>();
      final transport = CopilotCompatStdioServerTransport(stdin: stdin.stream);

      final onCloseFired = Completer<void>();
      transport.onclose = onCloseFired.complete;

      var done = false;
      unawaited(transport.done.then((_) => done = true));

      await transport.start();
      expect(done, isFalse);

      // The MCP host closing the connection surfaces as stdin EOF.
      await stdin.close();
      await transport.done.timeout(const Duration(seconds: 5));
      await onCloseFired.future.timeout(const Duration(seconds: 5));

      expect(done, isTrue);
    });

    test('done completes when close() is called after start()', () async {
      final stdin = StreamController<List<int>>();
      final transport = CopilotCompatStdioServerTransport(stdin: stdin.stream);

      await transport.start();
      await transport.close();

      await transport.done.timeout(const Duration(seconds: 5));
    });

    test('done completes even when close() is called before start()', () async {
      final transport = CopilotCompatStdioServerTransport(
        stdin: StreamController<List<int>>().stream,
      );

      await transport.close();

      await transport.done.timeout(const Duration(seconds: 5));
    });
  });
}
