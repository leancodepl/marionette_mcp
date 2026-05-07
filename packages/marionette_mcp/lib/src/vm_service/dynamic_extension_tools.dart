import 'dart:convert';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers MCP tools at runtime for each custom extension exposed by the
/// connected Flutter app via `registerMarionetteExtension`.
///
/// One call corresponds to one connection lifecycle: callers invoke
/// [registerAll] after `connect` succeeds, then [disableAll] on `disconnect`
/// to retire the registered tools.
///
/// Only extensions that ship an `inputSchema` get promoted — schema-less
/// extensions remain reachable through the generic `call_custom_extension`
/// tool, preserving backward compatibility with apps that haven't migrated.
class DynamicExtensionTools {
  DynamicExtensionTools({
    required McpServer server,
    required VmServiceConnector connector,
    required logging.Logger logger,
  })  : _server = server,
        _connector = connector,
        _logger = logger;

  final McpServer _server;
  final VmServiceConnector _connector;
  final logging.Logger _logger;
  final List<RegisteredTool> _registered = [];

  /// The tools registered by the most recent [registerAll] call that have
  /// not yet been disabled. Exposed for tests.
  List<RegisteredTool> get registeredTools => List.unmodifiable(_registered);

  /// Reads the connected app's custom extensions and promotes each one
  /// with an `inputSchema` to a first-class MCP tool.
  ///
  /// Tools whose name collides with a built-in (or another custom) tool
  /// are skipped with a warning — the operator sees the conflict in logs
  /// and renames their extension. Tools whose schema fails to parse are
  /// likewise skipped with a warning.
  Future<void> registerAll() async {
    final Map<String, dynamic> response;
    try {
      response = await _connector.listExtensions();
    } catch (err) {
      _logger.warning(
        'Failed to fetch custom extensions for dynamic registration; '
        'skipping. Generic call_custom_extension still works.',
        err,
      );
      return;
    }

    final extensionsRaw = response['extensions'];
    if (extensionsRaw is! List) {
      _logger.warning(
        'marionette.listExtensions response missing "extensions" list; '
        'got: $extensionsRaw',
      );
      return;
    }

    var registered = 0;
    var skippedNoSchema = 0;
    for (final ext in extensionsRaw) {
      if (ext is! Map) {
        _logger.warning('Skipping malformed extension entry: $ext');
        continue;
      }
      final name = ext['name'];
      if (name is! String || name.isEmpty) {
        _logger.warning('Skipping extension with missing/invalid name: $ext');
        continue;
      }
      final description = ext['description'] as String?;
      final schemaJson = ext['inputSchema'];
      if (schemaJson == null) {
        skippedNoSchema++;
        continue;
      }
      if (schemaJson is! Map<String, dynamic>) {
        _logger.warning(
          'Skipping extension "$name": inputSchema is not a JSON object',
        );
        continue;
      }

      final tool = _registerOne(
        name: name,
        description: description,
        schemaJson: schemaJson,
      );
      if (tool != null) {
        _registered.add(tool);
        registered++;
      }
    }

    _logger.info(
      'Promoted $registered custom extension(s) to MCP tools '
      '(${skippedNoSchema} schema-less extension(s) remain reachable via '
      'call_custom_extension).',
    );
  }

  /// Disables every tool registered by [registerAll] and forgets them.
  ///
  /// Uses [RegisteredTool.disable] rather than [RegisteredTool.remove] —
  /// the latter is broken in mcp_dart 2.1.0 (`update(name: null)` never
  /// deletes the entry from the registry). Disabled tools are filtered
  /// out of `tools/list` and rejected on call, which is the behavior we
  /// want.
  void disableAll() {
    if (_registered.isEmpty) return;
    for (final tool in _registered) {
      tool.disable();
    }
    _logger.info(
      'Disabled ${_registered.length} dynamic extension tool(s) on disconnect.',
    );
    _registered.clear();
  }

  RegisteredTool? _registerOne({
    required String name,
    required String? description,
    required Map<String, dynamic> schemaJson,
  }) {
    final ToolInputSchema schema;
    try {
      final parsed = JsonSchema.fromJson(schemaJson);
      if (parsed is! ToolInputSchema) {
        _logger.warning(
          'Skipping extension "$name": inputSchema parsed to '
          '${parsed.runtimeType} but MCP requires a JSON object schema.',
        );
        return null;
      }
      schema = parsed;
    } catch (err) {
      _logger.warning(
        'Skipping extension "$name": failed to parse inputSchema',
        err,
      );
      return null;
    }

    try {
      return _server.registerTool(
        name,
        description: description,
        inputSchema: schema,
        callback: (args, extra) async {
          return runTool(_logger, 'call extension "$name"', () async {
            final stringArgs = _coerceToStringMap(args);
            final response = await _connector.callCustomExtension(
              name,
              stringArgs,
            );
            return CallToolResult(
              content: [TextContent(text: jsonEncode(response))],
            );
          });
        },
      );
    } on ArgumentError catch (err) {
      // mcp_dart throws ArgumentError on duplicate name — most likely a
      // collision with a built-in marionette tool (tap, scroll_to, etc.)
      // or another already-registered custom extension.
      _logger.warning(
        'Skipping extension "$name": MCP tool name collision. '
        'Rename the extension on the Flutter side. Details: ${err.message}',
      );
      return null;
    }
  }
}

/// Coerces the typed JSON arguments validated against the extension's
/// `inputSchema` into the `Map<String, String>` shape that the Dart VM
/// service expects.
///
/// `int 42 → "42"`, `bool true → "true"`, `null → ""`, lists/maps →
/// `jsonEncode(value)` so callbacks that opt into nested structures can
/// still parse them. The Flutter callback is responsible for parsing
/// scalars back into the right Dart type.
///
/// Public for testing — internal callers go through the closure inside
/// [DynamicExtensionTools].
Map<String, dynamic> coerceToStringMap(Map<String, dynamic> args) =>
    _coerceToStringMap(args);

Map<String, dynamic> _coerceToStringMap(Map<String, dynamic> args) {
  final result = <String, dynamic>{};
  for (final entry in args.entries) {
    final value = entry.value;
    if (value == null) {
      result[entry.key] = '';
    } else if (value is String) {
      result[entry.key] = value;
    } else if (value is num || value is bool) {
      result[entry.key] = value.toString();
    } else {
      result[entry.key] = jsonEncode(value);
    }
  }
  return result;
}
