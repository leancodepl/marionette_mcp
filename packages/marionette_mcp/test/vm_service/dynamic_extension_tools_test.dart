import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/dynamic_extension_tools.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class _FakeConnector implements VmServiceConnector {
  _FakeConnector({
    required this.listExtensionsResponse,
    this.listExtensionsError,
  });

  final Map<String, dynamic> listExtensionsResponse;
  final Object? listExtensionsError;

  /// Records every callCustomExtension(name, args) invocation.
  final List<({String name, Map<String, dynamic> args})> calls = [];
  Map<String, dynamic> nextCustomResponse = const {};

  @override
  Future<Map<String, dynamic>> listExtensions() async {
    if (listExtensionsError != null) {
      throw listExtensionsError!;
    }
    return listExtensionsResponse;
  }

  @override
  Future<Map<String, dynamic>> callCustomExtension(
    String extensionName, [
    Map<String, dynamic> args = const {},
  ]) async {
    calls.add((name: extensionName, args: args));
    return nextCustomResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

McpServer _server() => McpServer(
      const Implementation(name: 'test-server', version: '0.0.0'),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(
          tools: ServerCapabilitiesTools(listChanged: true),
        ),
      ),
    );

void main() {
  group('DynamicExtensionTools.registerAll', () {
    test('registers one tool per schema-bearing extension', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'deckNavigation.goToSlide',
              'description': 'Navigate to a specific slide',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'slideIndex': {'type': 'integer'},
                },
                'required': ['slideIndex'],
              },
            },
            {
              'name': 'analytics.flush',
              'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
            },
          ],
        },
      );

      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: connector,
        logger: logging.Logger.detached('test'),
      );
      await dynamicTools.registerAll();

      final names = dynamicTools.registeredTools.map((t) => t.name).toSet();
      expect(names, {'deckNavigation.goToSlide', 'analytics.flush'});
    });

    test('skips schema-less extensions', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {'name': 'legacy.ext', 'description': 'No schema'},
          ],
        },
      );

      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: connector,
        logger: logging.Logger.detached('test'),
      );
      await dynamicTools.registerAll();

      expect(dynamicTools.registeredTools, isEmpty);
    });

    test('skips entries with malformed schema and keeps the rest', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            // Wrong inputSchema shape (string, not object).
            {'name': 'broken', 'inputSchema': 'not-a-map'},
            // Valid one — must still register.
            {
              'name': 'good',
              'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
            },
          ],
        },
      );

      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: connector,
        logger: logging.Logger.detached('test'),
      );
      await dynamicTools.registerAll();

      final names = dynamicTools.registeredTools.map((t) => t.name).toList();
      expect(names, ['good']);
    });

    test('skips when name collides with an already-registered tool',
        () async {
      final server = _server()
        ..registerTool(
          'tap', // Pretend this is a built-in name.
          description: 'built-in',
          inputSchema: const ToolInputSchema(properties: {}),
          callback: (_, __) async =>
              CallToolResult(content: const [TextContent(text: 'ok')]),
        );

      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'tap',
              'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
            },
          ],
        },
      );

      final dynamicTools = DynamicExtensionTools(
        server: server,
        connector: connector,
        logger: logging.Logger.detached('test'),
      );
      await dynamicTools.registerAll();

      // Collision — the dynamic registration should not add a second 'tap'.
      expect(dynamicTools.registeredTools, isEmpty);
    });

    test('fails gracefully when listExtensions throws', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {},
        listExtensionsError: const NotConnectedException(),
      );

      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: connector,
        logger: logging.Logger.detached('test'),
      );

      // Must not propagate — connect should still succeed even if dynamic
      // registration fails.
      await dynamicTools.registerAll();
      expect(dynamicTools.registeredTools, isEmpty);
    });
  });

  group('DynamicExtensionTools.disableAll', () {
    test('disables every registered tool and clears the list', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'a',
              'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
            },
            {
              'name': 'b',
              'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
            },
          ],
        },
      );

      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: connector,
        logger: logging.Logger.detached('test'),
      );
      await dynamicTools.registerAll();
      final captured = dynamicTools.registeredTools.toList();
      expect(captured.every((t) => t.enabled), isTrue);

      dynamicTools.disableAll();

      expect(dynamicTools.registeredTools, isEmpty);
      expect(captured.every((t) => !t.enabled), isTrue);
    });

    test('is a no-op when nothing is registered', () {
      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: _FakeConnector(listExtensionsResponse: const {}),
        logger: logging.Logger.detached('test'),
      );

      // Must not throw.
      dynamicTools.disableAll();
      expect(dynamicTools.registeredTools, isEmpty);
    });
  });

  group('coerceToStringMap', () {
    test('passes string values through unchanged', () {
      expect(coerceToStringMap({'k': 'v'}), {'k': 'v'});
    });

    test('stringifies numbers and booleans', () {
      expect(
        coerceToStringMap({'i': 42, 'd': 1.5, 'b': true}),
        {'i': '42', 'd': '1.5', 'b': 'true'},
      );
    });

    test('jsonEncodes nested structures', () {
      expect(
        coerceToStringMap({
          'list': [1, 2],
          'map': {'x': 1},
        }),
        {'list': '[1,2]', 'map': '{"x":1}'},
      );
    });

    test('replaces null with the empty string', () {
      expect(coerceToStringMap({'k': null}), {'k': ''});
    });
  });
}
