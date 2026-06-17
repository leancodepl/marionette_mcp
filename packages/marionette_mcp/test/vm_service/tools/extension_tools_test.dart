import 'dart:convert';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/tools/extension_tools.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// Captures the args forwarded to [callCustomExtension] so we can assert on the
/// exact wire shape produced by the coercion step.
class _CapturingConnector implements VmServiceConnector {
  final List<({String name, Map<String, dynamic> args})> calls = [];
  Map<String, dynamic> nextResponse = const {'ok': true};

  @override
  Future<Map<String, dynamic>> callCustomExtension(
    String extensionName, [
    Map<String, dynamic> args = const {},
  ]) async {
    calls.add((name: extensionName, args: args));
    return nextResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('callCustomExtension', () {
    late _CapturingConnector connector;
    late logging.Logger logger;

    setUp(() {
      connector = _CapturingConnector();
      logger = logging.Logger.detached('test');
    });

    test('forwards the extension name', () async {
      await callCustomExtension(connector, logger, {
        'extension': 'appNavigation.goToPage',
      });

      expect(connector.calls.single.name, 'appNavigation.goToPage');
    });

    test('stringifies scalar args before sending', () async {
      await callCustomExtension(connector, logger, {
        'extension': 'x',
        'args': {'i': 42, 'd': 1.5, 'b': true, 's': 'hi'},
      });

      expect(connector.calls.single.args, {
        'i': '42',
        'd': '1.5',
        'b': 'true',
        's': 'hi',
      });
    });

    test('jsonEncodes nested object/array args (not Dart toString)', () async {
      await callCustomExtension(connector, logger, {
        'extension': 'x',
        'args': {
          'range': {'min': 1, 'max': 9},
          'tags': ['a', 'b'],
        },
      });

      // The bug being fixed: previously these arrived as Dart's `{min: 1, ...}`
      // / `[a, b]` toString() form. They must now be valid JSON.
      expect(connector.calls.single.args, {
        'range': '{"min":1,"max":9}',
        'tags': '["a","b"]',
      });
      // And it must round-trip through a JSON parser.
      expect(
        jsonDecode(connector.calls.single.args['range'] as String),
        {'min': 1, 'max': 9},
      );
    });

    test('replaces null arg values with the empty string', () async {
      await callCustomExtension(connector, logger, {
        'extension': 'x',
        'args': {'maybe': null},
      });

      expect(connector.calls.single.args, {'maybe': ''});
    });

    test('sends an empty map when args are omitted', () async {
      await callCustomExtension(connector, logger, {'extension': 'x'});

      expect(connector.calls.single.args, isEmpty);
    });

    test('wraps the connector response as JSON text content', () async {
      connector.nextResponse = const {'result': 'done'};

      final result = await callCustomExtension(connector, logger, {
        'extension': 'x',
      });

      final content = result.content.single as TextContent;
      expect(jsonDecode(content.text), {'result': 'done'});
    });
  });
}
