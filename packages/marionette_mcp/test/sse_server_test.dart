@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'support/test_process.dart';

void main() {
  test(
    'legacy SSE initializes, lists tools and exits on SIGTERM while connected',
    () async {
      final app = await TestProcess.start([
        '--enable-vm-service=0',
        '--disable-service-auth-codes',
        'test/fixtures/vm_service_app.dart',
      ]);
      addTearDown(app.dispose);
      final vmUri = await app.vmServiceUri();

      // Pick an available loopback port before launching the actual executable.
      final reservation =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = reservation.port;
      await reservation.close();
      final server = await TestProcess.start([
        'run',
        'bin/marionette_mcp.dart',
        '--sse-port',
        '$port',
        '--log-level',
        'FINE',
      ]);
      addTearDown(server.dispose);
      await server.waitForStderr('Running MCP server on SSE port $port');

      final client = McpClient(
        const Implementation(name: 'sse-shutdown-test', version: '1'),
        options: McpClientOptions(protocol: McpProtocol.legacy),
      );
      addTearDown(() => client.close().timeout(const Duration(seconds: 5)));
      // The executable still exposes --sse-port for legacy clients.
      final transport =
          // ignore: deprecated_member_use
          SseClientTransport(Uri.parse('http://127.0.0.1:$port/sse'));
      await client.connect(transport).timeout(const Duration(seconds: 15));
      final catalog = await client.listTools().timeout(
            const Duration(seconds: 15),
          );
      expect(catalog.tools.map((tool) => tool.name), contains('connect'));
      final connected = await client
          .callTool(CallToolRequest(name: 'connect', arguments: {'uri': vmUri}))
          .timeout(const Duration(seconds: 15));
      expect(connected.isError, isFalse, reason: '${connected.content}');

      // Both the SSE session and VM connection remain active until shutdown.
      expect(server.process.kill(ProcessSignal.sigterm), isTrue);
      expect(
        await server.exitCodeWithin(const Duration(seconds: 10)),
        0,
        reason: server.errors.toString(),
      );
    },
    skip: Platform.isWindows ? 'SIGTERM requires POSIX signals' : false,
  );
}
