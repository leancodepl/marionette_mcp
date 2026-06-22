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
///
/// Extension names are sanitized to a client-safe MCP tool name (see
/// [sanitizeToolName]). The `namespace.method` convention is out of spec for
/// the underlying tool-calling APIs — Anthropic allows `[a-zA-Z0-9_]`, OpenAI
/// `[a-zA-Z0-9_-]`, both rejecting the `.` separator — and clients diverge on
/// how they cope (Claude Code rewrites the name transparently; VS Code Copilot
/// rejects anything outside `[a-z0-9_-]` and drops the tool). Sanitizing to
/// the strictest set keeps the tool usable everywhere. The underlying
/// extension is still invoked by its real name, so `appNavigation.goToPage` is
/// exposed as the tool `app_navigation_go_to_page` but dispatched to
/// `appNavigation.goToPage` on the VM service.
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

  /// Every tool we have ever registered with the server, keyed by the
  /// (sanitized) MCP tool name. Persists across connect/disconnect cycles so
  /// we can revive entries via [RegisteredTool.update] instead of hitting the
  /// duplicate-name guard in [McpServer.registerTool].
  final Map<String, RegisteredTool> _pool = {};

  /// Maps a sanitized tool name back to the real extension name that owns it.
  /// Used to tell a same-extension revival (across reconnects) apart from two
  /// distinct extensions whose names sanitize to the same tool name (a
  /// collision we must skip rather than silently clobber). Persists for the
  /// lifetime of the instance, mirroring [_pool].
  final Map<String, String> _extensionByTool = {};

  /// Tool names that are currently enabled (i.e. promoted in this connect
  /// cycle).
  final Set<String> _active = {};

  /// The tools enabled by the most recent [registerAll] call that have not
  /// yet been disabled. Exposed for tests.
  List<RegisteredTool> get registeredTools =>
      List.unmodifiable(_active.map((name) => _pool[name]!));

  /// The real extension name backing the promoted MCP tool [toolName], or
  /// null if no such tool has been pooled. The promoted tool name is
  /// sanitized (see [sanitizeToolName]); this maps it back to the name the
  /// VM service extension is actually invoked with. Exposed for introspection
  /// and tests.
  String? extensionNameForTool(String toolName) => _extensionByTool[toolName];

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

      final toolName = sanitizeToolName(name);
      final tool = _promote(
        extensionName: name,
        toolName: toolName,
        description: description,
        schemaJson: schemaJson,
      );
      if (tool != null) {
        _active.add(toolName);
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
    required String extensionName,
    required String toolName,
    required String? description,
    required Map<String, dynamic> schemaJson,
  }) {
    final ToolInputSchema schema;
    try {
      final parsed = JsonSchema.fromJson(schemaJson);
      if (parsed is! ToolInputSchema) {
        _logger.warning(
          'Skipping extension "$extensionName": inputSchema parsed to '
          '${parsed.runtimeType} but MCP requires a JSON object schema.',
        );
        return null;
      }
      schema = parsed;
    } catch (err) {
      _logger.warning(
        'Skipping extension "$extensionName": failed to parse inputSchema',
        err,
      );
      return null;
    }

    // The extension is always invoked by its real name; only the MCP tool
    // name is sanitized for clients that restrict the character set.
    final callback = _buildCallback(extensionName);
    final effectiveDescription =
        _describe(extensionName, toolName, description);

    final pooled = _pool[toolName];
    if (pooled != null) {
      if (_extensionByTool[toolName] != extensionName) {
        // Two distinct extensions sanitize to the same tool name. Reviving in
        // place would silently hijack the first one's tool, so skip instead.
        _logger.warning(
          'Skipping extension "$extensionName": its sanitized MCP tool name '
          '"$toolName" collides with extension "${_extensionByTool[toolName]}". '
          'Rename one of them on the Flutter side.',
        );
        return null;
      }
      // Previously seen — revive in place. Re-registering by name would
      // throw because mcp_dart's `disable()` leaves the entry in the
      // server's tool map.
      pooled.update(
        description: effectiveDescription,
        inputSchema: schema,
        callback: FunctionToolCallback(callback),
        enabled: true,
      );
      return pooled;
    }

    try {
      final tool = _server.registerTool(
        toolName,
        description: effectiveDescription,
        inputSchema: schema,
        callback: callback,
      );
      _pool[toolName] = tool;
      _extensionByTool[toolName] = extensionName;
      return tool;
    } on ArgumentError catch (err) {
      // mcp_dart throws ArgumentError on duplicate name — most likely a
      // collision with a built-in marionette tool (tap, scroll_to, etc.).
      // We don't pool colliding names so subsequent reconnects re-emit the
      // warning.
      _logger.warning(
        'Skipping extension "$extensionName" (tool name "$toolName"): MCP '
        'tool name collision. Rename the extension on the Flutter side. '
        'Details: ${err.message}',
      );
      return null;
    }
  }

  /// Builds the tool description, appending the real extension name when it
  /// differs from the sanitized tool name so agents can still reach it via
  /// `call_custom_extension` and understand what the tool maps to.
  String? _describe(String extensionName, String toolName, String? base) {
    if (toolName == extensionName) return base;
    final note = 'Custom extension: $extensionName';
    return base == null || base.isEmpty ? note : '$base\n\n$note';
  }

  ToolFunction _buildCallback(String extensionName) {
    return (args, extra) async {
      return runTool(_logger, 'call extension "$extensionName"', () async {
        final stringArgs = coerceToStringMap(args);
        final response = await _connector.callCustomExtension(
          extensionName,
          stringArgs,
        );
        return CallToolResult(
          content: [TextContent(text: jsonEncode(response))],
        );
      });
    };
  }
}

/// Maps a custom-extension name to an MCP tool name accepted across clients.
/// The target set `[a-z0-9_-]` is the strictest in common use (VS Code Copilot
/// enforces it); it also stays within the `.`-rejecting character sets the
/// Anthropic and OpenAI tool-calling APIs require, which the `namespace.method`
/// convention would otherwise violate.
///
/// A name already within the allowed set is returned verbatim — including
/// any leading, trailing, or repeated `_`/`-` the author chose — so valid
/// names are never silently rewritten. Otherwise the transform lower-cases
/// the name, inserts `_` at camelCase boundaries so `goToPage` reads as
/// `go_to_page`, replaces every other disallowed character (e.g. the `.`
/// namespace separator) with `_`, then collapses and trims runs of `_`. For
/// example `appNavigation.goToPage` becomes `app_navigation_go_to_page`.
String sanitizeToolName(String name) {
  // Already client-safe: leave it exactly as the author wrote it. Collapsing
  // or trimming here would change valid names (e.g. `__foo__` -> `foo`) and
  // could create surprising collisions.
  if (RegExp(r'^[a-z0-9_-]+$').hasMatch(name)) return name;

  final withBoundaries = name.replaceAllMapped(
    RegExp('[a-z0-9][A-Z]'),
    (m) => '${m[0]![0]}_${m[0]![1]}',
  );
  final sanitized = withBoundaries
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9_-]'), '_')
      .replaceAll(RegExp('_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.isEmpty ? '_' : sanitized;
}
