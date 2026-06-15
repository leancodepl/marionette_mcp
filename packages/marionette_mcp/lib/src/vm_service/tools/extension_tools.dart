import 'dart:convert';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/tools/arg_coercion.dart';
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers MCP tools for discovering and invoking custom VM service
/// extensions registered by the Flutter app:
/// `list_custom_extensions`, `call_custom_extension`.
void registerExtensionTools(
  McpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server
    ..registerTool(
      'list_custom_extensions',
      description:
          'Lists all custom VM service extensions registered by the Flutter '
          'app (outside of the built-in Marionette extensions). Each '
          'extension includes its name and an optional description. Use this '
          'to discover what app-specific extensions are available before '
          'calling them with call_custom_extension. '
          'Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'List Custom Extensions',
        readOnlyHint: true,
        idempotentHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Listing custom extensions');
        return runTool(logger, 'list custom extensions', () async {
          final response = await connector.listExtensions();
          final extensions = (response['extensions'] as List<dynamic>)
              .cast<Map<String, dynamic>>();

          if (extensions.isEmpty) {
            return CallToolResult(
              content: [
                const TextContent(text: 'No custom extensions registered.'),
              ],
            );
          }

          final buffer = StringBuffer()
            ..writeln('Found ${extensions.length} custom extension(s):\n');

          for (final ext in extensions) {
            final name = ext['name'] as String;
            final description = ext['description'] as String?;
            buffer.write('- $name');
            if (description != null) {
              buffer.write(': $description');
            }
            buffer.writeln();
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
          );
        });
      },
    )
    // Intentionally no readOnlyHint or idempotentHint on call_custom_extension
    // since the behavior depends entirely on the target extension.
    ..registerTool(
      'call_custom_extension',
      description:
          'Calls a custom VM service extension registered by the Flutter app. '
          'This is an escape hatch for interacting with app-specific '
          'extensions that are not part of marionette\'s built-in tools. '
          'For marionette features, use the dedicated tools instead. '
          'The extension name should not include the "ext.flutter." prefix as '
          'it is added automatically. For example, use '
          '"deckNavigation.goToSlide" instead of '
          '"ext.flutter.deckNavigation.goToSlide". '
          'Arguments are passed as string key-value pairs. '
          'The available extensions depend on what the connected Flutter app '
          'has registered. Check the app\'s source code for available extensions. '
          'Requires an active connection established via connect.',
      annotations: const ToolAnnotations(title: 'Call Custom Extension'),
      inputSchema: ToolInputSchema(
        properties: {
          'extension': JsonSchema.string(
            description: 'The extension name without the "ext.flutter." prefix '
                '(e.g., "deckNavigation.goToSlide").',
          ),
          'args': JsonSchema.object(
            description: 'Optional key-value pairs to pass as arguments. '
                'Scalars are stringified and nested object/array values are '
                'JSON-encoded before being sent to the VM service extension.',
            properties: {},
          ),
        },
        required: ['extension'],
      ),
      callback: (args, extra) => callCustomExtension(connector, logger, args),
    );
}

/// Handles a `call_custom_extension` invocation: coerces the supplied `args`
/// into the wire shape, forwards them to [connector], and wraps the response.
///
/// Extracted from the tool callback so the coercion contract can be exercised
/// in isolation. Args go through [coerceToStringMap] — the same path the
/// dynamically-promoted extension tools use — so both produce identical wire
/// args: scalars are stringified and nested object/array values become valid
/// JSON (not Dart's un-parseable `toString()` form).
Future<CallToolResult> callCustomExtension(
  VmServiceConnector connector,
  logging.Logger logger,
  Map<String, dynamic> args,
) {
  final extensionName = args['extension'] as String;
  final extensionArgs = coerceToStringMap(
    (args['args'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
  );
  logger.info(
    'Calling custom extension: $extensionName with args: $extensionArgs',
  );
  return runTool(logger, 'call custom extension', () async {
    final response = await connector.callCustomExtension(
      extensionName,
      extensionArgs,
    );
    return CallToolResult(
      content: [TextContent(text: jsonEncode(response))],
    );
  });
}
