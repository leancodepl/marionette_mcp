import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/dynamic_extension_tools.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

class _FakeConnector implements VmServiceConnector {
  _FakeConnector({
    Map<String, dynamic> listExtensionsResponse = const {},
    this.listExtensionsError,
  }) : _listExtensionsResponse = listExtensionsResponse;

  Map<String, dynamic> _listExtensionsResponse;
  final Object? listExtensionsError;

  /// Replace the response that the next [listExtensions] call returns.
  /// Lets tests model what the app exposes across consecutive connect cycles.
  set listExtensionsResponse(Map<String, dynamic> value) =>
      _listExtensionsResponse = value;

  /// Records every callCustomExtension(name, args) invocation.
  final List<({String name, Map<String, dynamic> args})> calls = [];
  Map<String, dynamic> nextCustomResponse = const {};

  @override
  Future<Map<String, dynamic>> listExtensions() async {
    if (listExtensionsError != null) {
      throw listExtensionsError!;
    }
    return _listExtensionsResponse;
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

  group('DynamicExtensionTools reconnect', () {
    test(
        're-registers same extension after disable without name collision '
        'and revives the same RegisteredTool instance', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'foo',
              'description': 'first',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{},
              },
            },
          ],
        },
      );

      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: connector,
        logger: logging.Logger.detached('test'),
      );

      // Cycle 1.
      await dynamicTools.registerAll();
      expect(dynamicTools.registeredTools, hasLength(1));
      final firstInstance = dynamicTools.registeredTools.single;
      expect(firstInstance.enabled, isTrue);

      // Disconnect — emulates the disable-on-disconnect path.
      dynamicTools.disableAll();
      expect(dynamicTools.registeredTools, isEmpty);
      expect(firstInstance.enabled, isFalse);

      // Cycle 2 with the same payload — must not throw, must revive in
      // place.
      await dynamicTools.registerAll();

      expect(dynamicTools.registeredTools, hasLength(1));
      final secondInstance = dynamicTools.registeredTools.single;
      expect(
        identical(firstInstance, secondInstance),
        isTrue,
        reason: 'reconnect should reuse the pooled RegisteredTool',
      );
      expect(secondInstance.enabled, isTrue);
    });

    test('reflects changed description and inputSchema on revival', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'foo',
              'description': 'v1',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{},
              },
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
      final tool = dynamicTools.registeredTools.single;
      expect(tool.description, 'v1');
      expect(tool.inputSchema?.properties, isEmpty);

      dynamicTools.disableAll();

      connector.listExtensionsResponse = const {
        'extensions': [
          {
            'name': 'foo',
            'description': 'v2',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'count': {'type': 'integer'},
              },
              'required': ['count'],
            },
          },
        ],
      };
      await dynamicTools.registerAll();

      expect(tool.description, 'v2');
      expect(tool.inputSchema?.properties?.keys, ['count']);
    });

    test(
        'extensions that disappear on reconnect stay disabled and leave the '
        'present ones enabled', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'foo',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{},
              },
            },
            {
              'name': 'bar',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{},
              },
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
      final byName = {
        for (final t in dynamicTools.registeredTools) t.name: t,
      };
      expect(byName.keys, containsAll(['foo', 'bar']));

      dynamicTools.disableAll();

      // App now exposes only `foo`.
      connector.listExtensionsResponse = const {
        'extensions': [
          {
            'name': 'foo',
            'inputSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
            },
          },
        ],
      };
      await dynamicTools.registerAll();

      final activeNames =
          dynamicTools.registeredTools.map((t) => t.name).toSet();
      expect(activeNames, {'foo'});
      expect(byName['foo']!.enabled, isTrue);
      expect(byName['bar']!.enabled, isFalse);
    });

    test('built-in name collisions are skipped on every cycle', () async {
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
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{},
              },
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
      expect(dynamicTools.registeredTools, isEmpty);

      dynamicTools.disableAll();

      // Second cycle with the same colliding extension — still skipped,
      // and we still don't fall over because the collision name is not
      // pooled (so we re-attempt registerTool, which throws and is
      // caught again).
      await dynamicTools.registerAll();
      expect(dynamicTools.registeredTools, isEmpty);
    });
  });
}
