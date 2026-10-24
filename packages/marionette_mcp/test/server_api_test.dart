@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/marionette_mcp.dart';
import 'package:marionette_mcp/runtime.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  for (final protocol in [McpProtocol.legacy, McpProtocol.stable]) {
    test('public client preserves the original tool catalog on $protocol',
        () async {
      final client = McpClient(
        const Implementation(name: 'marionette-api-test', version: '1'),
        options: McpClientOptions(protocol: protocol),
      );
      final transport = StdioClientTransport(StdioServerParameters(
        command: Platform.resolvedExecutable,
        args: ['run', 'bin/marionette_mcp.dart', '--log-level', 'SEVERE'],
        restartOnUnexpectedExit: false,
      ));
      addTearDown(client.close);
      await client.connect(transport);

      // Captured from the original 0.7.0 server with mcp_dart 2.4.3, before
      // changing any registrations. This is the client-visible contract.
      final expected = (jsonDecode(
        File('test/fixtures/tools_catalog.json').readAsStringSync(),
      ) as List)
          .cast<Map<String, dynamic>>();
      if (protocol == McpProtocol.stable) {
        // SDK stateless discovery sorts the catalog and omits legacy Tasks
        // execution metadata. Tool-owned metadata remains identical.
        expected.sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String));
        for (final tool in expected) {
          tool.remove('execution');
        }
      }
      final catalog = await client.listTools();
      expect(catalog.tools.map((tool) => tool.toJson()).toList(), expected);

      final result = await client.callTool(
        const CallToolRequest(name: 'get_logs', arguments: {}),
      );
      expect(result.isError, isTrue);
      expect(result.content.whereType<TextContent>().single.text,
          contains('Not connected'));
    });
  }

  test('public server composition accepts an owned runtime dependency',
      () async {
    final connector = _TrackingConnector();
    final context = VmServiceContext(connector: connector);
    final server = createMcpServer(context: context);
    try {
      await context.dispose();
      expect(connector.disconnections, 1);
    } finally {
      await server.close();
    }
  });
}

class _TrackingConnector extends VmServiceConnector {
  int disconnections = 0;

  @override
  Future<void> disconnect() async {
    disconnections++;
    await super.disconnect();
  }
}
