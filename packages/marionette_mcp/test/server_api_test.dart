@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
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
      final actual = catalog.tools.map((tool) => tool.toJson()).toList();
      // Structured results intentionally add an output contract. All original
      // names, input schemas, descriptions and annotations stay compatible.
      for (final tool in actual) {
        expect(tool.remove('outputSchema'), isNotNull,
            reason: '${tool['name']} must advertise its structured result');
      }
      expect(actual, expected);

      final result = await client.callTool(
        const CallToolRequest(name: 'get_logs', arguments: {}),
      );
      expect(result.isError, isTrue);
      expect(result.content.whereType<TextContent>().single.text,
          contains('Not connected'));
    });
  }

  for (final protocol in [McpProtocol.legacy, McpProtocol.stable]) {
    test('public client receives validated structured results on $protocol',
        () async {
      final context = VmServiceContext(connector: _OutputConnector());
      final server = createMcpServer(context: context);
      final client = McpClient(
        const Implementation(name: 'structured-api-test', version: '1'),
        options: McpClientOptions(protocol: protocol),
      );
      final toServer = StreamController<List<int>>();
      final toClient = StreamController<List<int>>();
      addTearDown(() async {
        await client.close();
        await context.dispose();
        await server.close();
      });
      await server.connect(
          IOStreamTransport(stream: toServer.stream, sink: toClient.sink));
      await client.connect(
          IOStreamTransport(stream: toClient.stream, sink: toServer.sink));
      Future<CallToolResult> call(String name,
              [Map<String, dynamic> args = const {}]) =>
          client.callTool(CallToolRequest(name: name, arguments: args));
      final connected = await call('connect', {'uri': 'ws://fixture/ws'});
      expect(connected.isError, isFalse);
      expect(connected.structuredContent, {
        'uri': 'ws://fixture/ws',
        'sessionReportsEnabled': false,
      });
      final logs = await call('get_logs');
      expect(logs.structuredContent, {
        'logs': ['ready'],
        'count': 1
      });
      expect((logs.content.single as TextContent).text, contains('ready'));
      final reloaded = await call('hot_reload');
      expect(reloaded.structuredContent,
          {'message': 'Hot reload completed successfully'});
      final screenshots = await call('take_screenshots');
      expect(screenshots.structuredContent, {'count': 0, 'inline': true});
      final dynamicTool = (await client.listTools())
          .tools
          .singleWhere((t) => t.name == 'app_echo');
      expect(dynamicTool.outputSchema, isNotNull);
      final echoed = await call('app_echo', {'value': 'hello'});
      expect(echoed.structuredContent, {
        'response': {
          'value': 'hello',
          'nested': {'ok': true}
        }
      });
      expect(jsonDecode((echoed.content.single as TextContent).text),
          echoed.structuredContent!['response']);
      final disconnected = await call('disconnect');
      expect(disconnected.structuredContent, {'disconnected': true});
      expect((await client.listTools()).tools.any((t) => t.name == 'app_echo'),
          isFalse);
      final failed = await call('get_logs');
      expect(failed.isError, isTrue);
      expect(failed.structuredContent, isNull);
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

class _OutputConnector extends VmServiceConnector {
  bool _connected = false;

  @override
  Future<void> connect(String uri) async => _connected = true;

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<String> getVersion() async => version;

  @override
  Future<bool> getSessionReportsEnabled() async => false;

  @override
  Future<bool> hotReload() async => true;

  @override
  Future<Map<String, dynamic>> getLogs() async {
    if (!_connected) throw StateError('Not connected');
    return {
      'logs': ['ready'],
      'count': 1
    };
  }

  @override
  Future<Map<String, dynamic>> takeScreenshots() async =>
      {'screenshots': <String>[]};

  @override
  Future<Map<String, dynamic>> listExtensions() async => {
        'extensions': [
          {
            'name': 'app.echo',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'value': {'type': 'string'}
              },
              'required': ['value']
            }
          },
        ],
      };

  @override
  Future<Map<String, dynamic>> callCustomExtension(String extensionName,
          [Map<String, dynamic> args = const {}]) async =>
      {
        'value': args['value'],
        'nested': {'ok': true},
      };
}
