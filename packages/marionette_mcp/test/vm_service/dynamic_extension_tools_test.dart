import 'dart:async';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/tools/dynamic_extension_tools.dart';
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
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{}
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

      // Tool names are sanitized for strict clients; the dotted/camelCase
      // extension names map to `[a-z0-9_-]` tool names.
      final names = dynamicTools.registeredTools.map((t) => t.name).toSet();
      expect(names, {'deck_navigation_go_to_slide', 'analytics_flush'});
    });

    test(
        'sanitizes camelCase + dotted names but dispatches to the real '
        'extension name', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'appNavigation.goToPage',
              'description': 'Navigates to a page by name.',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'page': {'type': 'string'},
                },
                'required': ['page'],
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
      // Exposed to clients under a sanitized name...
      expect(tool.name, 'app_navigation_go_to_page');
      // ...but the real extension name is preserved for dispatch.
      expect(
        dynamicTools.extensionNameForTool('app_navigation_go_to_page'),
        'appNavigation.goToPage',
      );
      // The description records the real name so it stays reachable via
      // call_custom_extension.
      expect(tool.description, contains('appNavigation.goToPage'));
    });

    test('leaves already-valid tool names (and their descriptions) unchanged',
        () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'analytics_flush',
              'description': 'Flush analytics.',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{}
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
      expect(tool.name, 'analytics_flush');
      // No rename → description is left exactly as the author wrote it.
      expect(tool.description, 'Flush analytics.');
    });

    test(
        'skips a second extension whose name sanitizes to an '
        'already-claimed tool name', () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'fooBar',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{}
              },
            },
            {
              // Distinct extension, same sanitized tool name (`foo_bar`).
              'name': 'foo.bar',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{}
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

      // Only the first claimant is registered; the colliding one is skipped.
      final names = dynamicTools.registeredTools.map((t) => t.name).toList();
      expect(names, ['foo_bar']);
      expect(dynamicTools.extensionNameForTool('foo_bar'), 'fooBar');
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
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{}
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

      final names = dynamicTools.registeredTools.map((t) => t.name).toList();
      expect(names, ['good']);
    });

    test('skips when name collides with an already-registered tool', () async {
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
                'properties': <String, dynamic>{}
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

  group('DynamicExtensionTools.removeAll', () {
    test('removes every registered tool and releases its registry name',
        () async {
      final connector = _FakeConnector(
        listExtensionsResponse: const {
          'extensions': [
            {
              'name': 'a',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{}
              },
            },
            {
              'name': 'b',
              'inputSchema': {
                'type': 'object',
                'properties': <String, dynamic>{}
              },
            },
          ],
        },
      );

      final server = _server();
      final dynamicTools = DynamicExtensionTools(
        server: server,
        connector: connector,
        logger: logging.Logger.detached('test'),
      );
      await dynamicTools.registerAll();
      final captured = dynamicTools.registeredTools.toList();
      expect(captured.every((t) => t.enabled), isTrue);

      dynamicTools.removeAll();

      expect(dynamicTools.registeredTools, isEmpty);
      for (final tool in captured) {
        expect(dynamicTools.extensionNameForTool(tool.name), isNull);
        // Reusing the exact names would throw if removal left registry entries.
        server.registerTool(
          tool.name,
          callback: (_, __) async => CallToolResult(content: []),
        );
      }
    });

    test('is a no-op when nothing is registered', () {
      final dynamicTools = DynamicExtensionTools(
        server: _server(),
        connector: _FakeConnector(listExtensionsResponse: const {}),
        logger: logging.Logger.detached('test'),
      );

      // Must not throw.
      dynamicTools.removeAll();
      expect(dynamicTools.registeredTools, isEmpty);
    });
  });

  group('DynamicExtensionTools reconnect', () {
    test('re-registers the same extension with a fresh handle after removal',
        () async {
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

      // Disconnect releases the old registrations.
      dynamicTools.removeAll();
      expect(dynamicTools.registeredTools, isEmpty);
      expect(dynamicTools.extensionNameForTool(firstInstance.name), isNull);

      // Cycle 2 with the same payload must register without a collision.
      await dynamicTools.registerAll();

      expect(dynamicTools.registeredTools, hasLength(1));
      final secondInstance = dynamicTools.registeredTools.single;
      expect(
        identical(firstInstance, secondInstance),
        isFalse,
        reason: 'reconnect registers a fresh tool after removing the old one',
      );
      expect(secondInstance.enabled, isTrue);
    });

    test('reflects changed description and inputSchema on reconnect', () async {
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

      dynamicTools.removeAll();

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

      final reconnected = dynamicTools.registeredTools.single;
      expect(reconnected.description, 'v2');
      expect(reconnected.inputSchema?.properties?.keys, ['count']);
    });

    test('extensions that disappear on reconnect release their names',
        () async {
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

      dynamicTools.removeAll();

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
      expect(dynamicTools.extensionNameForTool('bar'), isNull);
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

      dynamicTools.removeAll();

      // The built-in still owns this name across connection cycles.
      await dynamicTools.registerAll();
      expect(dynamicTools.registeredTools, isEmpty);
    });
  });

  test('disconnect retires an in-flight dynamic tool discovery', () async {
    final connector = _DeferredConnector();
    final tools = DynamicExtensionTools(
      server: _server(),
      connector: connector,
      logger: logging.Logger.detached('test'),
    );
    final pending = tools.registerAll();
    tools.removeAll();
    connector.response.complete({
      'extensions': [
        {
          'name': 'late',
          'inputSchema': {'type': 'object', 'properties': {}}
        },
      ],
    });
    await pending;
    expect(tools.registeredTools, isEmpty);
    expect(tools.extensionNameForTool('late'), isNull);
  });

  group('sanitizeToolName', () {
    test('rewrites camelCase + dotted names', () {
      expect(sanitizeToolName('appNavigation.goToPage'),
          'app_navigation_go_to_page');
      expect(sanitizeToolName('analytics.flush'), 'analytics_flush');
    });

    test('returns names already in [a-z0-9_-] verbatim', () {
      // Including unusual-but-valid shapes: collapsing/trimming here would
      // silently rewrite a name the author deliberately chose.
      for (final name in [
        'analytics_flush',
        'already_valid-name',
        'a',
        '__foo__',
        'a--b'
      ]) {
        expect(sanitizeToolName(name), name, reason: name);
      }
    });

    test('never yields an empty name', () {
      expect(sanitizeToolName('...'), '_');
    });
  });
}

class _DeferredConnector extends _FakeConnector {
  final response = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> listExtensions() => response.future;
}
