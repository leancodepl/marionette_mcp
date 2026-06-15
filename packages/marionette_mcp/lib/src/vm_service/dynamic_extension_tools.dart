import 'dart:convert';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/tools/arg_coercion.dart';
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers MCP tools at runtime for each custom extension exposed by the
/// connected Flutter app via `registerMarionetteExtension`.
///
/// A single instance lives for the lifetime of the MCP server and is reused
/// across connect/disconnect cycles. Callers invoke [registerAll] after
/// `connect` succeeds, then [disableAll] on `disconnect` to retire the
/// registered tools. On a subsequent [registerAll] previously-disabled tools
/// are revived in place via [RegisteredTool.update] rather than re-registered
/// — re-registering by name throws in mcp_dart 2.1.0 because [disable]
/// leaves the entry in the server's tool map (and [RegisteredTool.remove]
/// is broken — see [disableAll]).
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

  /// Every tool we have ever registered with the server, keyed by name.
  /// Persists across connect/disconnect cycles so we can revive entries via
  /// [RegisteredTool.update] instead of hitting the duplicate-name guard in
  /// [McpServer.registerTool].
  final Map<String, RegisteredTool> _pool = {};

  /// Names that are currently enabled (i.e. promoted in this connect cycle).
  final Set<String> _active = {};

  /// The tools enabled by the most recent [registerAll] call that have not
  /// yet been disabled. Exposed for tests.
  List<RegisteredTool> get registeredTools =>
      List.unmodifiable(_active.map((name) => _pool[name]!));

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

      final tool = _promote(
        name: name,
        description: description,
        schemaJson: schemaJson,
      );
      if (tool != null) {
        _active.add(name);
        registered++;
      }
    }

    _logger.info(
      'Promoted $registered custom extension(s) to MCP tools '
      '(${skippedNoSchema} schema-less extension(s) remain reachable via '
      'call_custom_extension).',
    );
  }

  /// Disables every tool currently enabled by [registerAll] but keeps the
  /// references in the pool so the next [registerAll] can revive them via
  /// [RegisteredTool.update].
  ///
  /// We can't drop them from the server because [RegisteredTool.remove] is
  /// broken in mcp_dart 2.1.0 (`update(name: null)` never deletes the entry
  /// from the registry). Disabled tools are filtered out of `tools/list`
  /// and rejected on call, which is the behavior we want; the registry
  /// entry just stays squatting on its name and we re-enable it next time.
  void disableAll() {
    if (_active.isEmpty) return;
    for (final name in _active) {
      _pool[name]!.disable();
    }
    _logger.info(
      'Disabled ${_active.length} dynamic extension tool(s) on disconnect.',
    );
    _active.clear();
  }

  RegisteredTool? _promote({
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

    final callback = _buildCallback(name);

    final pooled = _pool[name];
    if (pooled != null) {
      // Previously seen — revive in place. Re-registering by name would
      // throw because mcp_dart's `disable()` leaves the entry in the
      // server's tool map.
      pooled.update(
        description: description,
        inputSchema: schema,
        callback: FunctionToolCallback(callback),
        enabled: true,
      );
      return pooled;
    }

    try {
      final tool = _server.registerTool(
        name,
        description: description,
        inputSchema: schema,
        callback: callback,
      );
      _pool[name] = tool;
      return tool;
    } on ArgumentError catch (err) {
      // mcp_dart throws ArgumentError on duplicate name — most likely a
      // collision with a built-in marionette tool (tap, scroll_to, etc.)
      // or another already-registered custom extension. We don't pool
      // colliding names so subsequent reconnects re-emit the warning.
      _logger.warning(
        'Skipping extension "$name": MCP tool name collision. '
        'Rename the extension on the Flutter side. Details: ${err.message}',
      );
      return null;
    }
  }

  ToolFunction _buildCallback(String name) {
    return (args, extra) async {
      return runTool(_logger, 'call extension "$name"', () async {
        final stringArgs = coerceToStringMap(args);
        final response = await _connector.callCustomExtension(
          name,
          stringArgs,
        );
        return CallToolResult(
          content: [TextContent(text: jsonEncode(response))],
        );
      });
    };
  }
}
