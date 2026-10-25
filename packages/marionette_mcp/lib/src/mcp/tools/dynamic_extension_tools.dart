import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/step_logging.dart';
import 'package:marionette_mcp/src/mcp/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/tools/arg_coercion.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'base_tool.dart';
import 'tool_results.dart';

/// Promotes schema-bearing app extensions for the current connection.
/// Schema-less extensions remain available through `call_custom_extension`.
/// Names are sanitized for clients; VM calls retain the original extension name.
/// Disconnect removes registrations; reconnect discovers fresh schemas.
class DynamicExtensionTools {
  DynamicExtensionTools({
    required McpServer server,
    required VmServiceConnector connector,
    required logging.Logger logger,
    StepLogger? stepLogger,
  })  : _server = server,
        _connector = connector,
        _logger = logger,
        _stepLogger = stepLogger;

  final McpServer _server;
  final VmServiceConnector _connector;
  final logging.Logger _logger;
  final StepLogger? _stepLogger;

  final Map<String, RegisteredTool> _tools = {};
  final Map<String, String> _extensionByTool = {};
  int _generation = 0;

  /// Snapshot of active registrations.
  List<RegisteredTool> get registeredTools => List.unmodifiable(_tools.values);

  /// Original VM extension name for a sanitized MCP tool name.
  String? extensionNameForTool(String toolName) => _extensionByTool[toolName];

  /// Discovers schema-bearing extensions, skipping malformed schemas and
  /// conflicting names with a warning.
  Future<void> registerAll() async {
    removeAll();
    final generation = _generation;
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

    // A disconnect may finish while the app's listExtensions call is pending.
    if (generation != _generation) return;

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
        registered++;
      }
    }

    _logger.info(
      'Promoted $registered custom extension(s) to MCP tools '
      '(${skippedNoSchema} schema-less extension(s) remain reachable via '
      'call_custom_extension).',
    );
  }

  /// Removes registrations and releases their names for the next connection.
  void removeAll() {
    ++_generation;
    for (final tool in _tools.values) {
      tool.remove();
    }
    _tools.clear();
    _extensionByTool.clear();
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
    final effectiveDescription =
        _describe(extensionName, toolName, description);
    final definition = CustomExtensionTool(
      name: toolName,
      extensionName: extensionName,
      description: effectiveDescription,
      inputSchema: schema,
      connector: _connector,
      logger: _logger,
    );
    final stepLogger = _stepLogger;
    final callback = stepLogger == null
        ? definition.execute
        : withStepLogging(stepLogger, toolName, definition.execute);

    final existing = _tools[toolName];
    if (existing != null) {
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
      // Repeated entries for the same extension update its current schema.
      existing.update(
        description: definition.description,
        inputSchema: schema,
        outputSchema: definition.outputSchema,
        callback: FunctionToolCallback(callback),
        enabled: true,
      );
      return existing;
    }

    try {
      final tool = _server.registerTool(
        toolName,
        description: definition.description,
        inputSchema: schema,
        outputSchema: definition.outputSchema,
        callback: callback,
      );
      _tools[toolName] = tool;
      _extensionByTool[toolName] = extensionName;
      return tool;
    } on ArgumentError catch (err) {
      // mcp_dart throws ArgumentError on duplicate name — most likely a
      // collision with a built-in marionette tool (tap, scroll_to, etc.).
      // A conflicting built-in remains untouched across reconnects.
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
}

/// Converts extension names to the client-safe `[a-z0-9_-]` set.
/// Already-valid names stay unchanged to avoid collisions. Otherwise camel-case
/// boundaries and punctuation become underscores: `app.goToPage` → `app_go_to_page`.
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

/// A schema-bearing app extension promoted into the common typed tool catalog.
class CustomExtensionTool extends BaseTool {
  CustomExtensionTool({
    required this.name,
    required this.extensionName,
    required String? description,
    required this.inputSchema,
    required this.connector,
    required this.logger,
  }) : _description = description;

  @override
  final String name;
  final String extensionName;
  final String? _description;
  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String? get description => _description;

  @override
  final ToolInputSchema inputSchema;

  @override
  ToolOutputSchema get outputSchema => extensionResponseOutputSchema;

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) =>
      runTool(logger, 'call extension "$extensionName"', () async {
        final response = await connector.callCustomExtension(
          extensionName,
          coerceToStringMap(args),
        );
        return extensionResponseResult(response);
      });
}
