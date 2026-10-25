import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/tools/arg_coercion.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'base_tool.dart';
import 'tool_results.dart';

/// MCP tool `list_custom_extensions`.
class ListCustomExtensionsTool extends BaseTool {
  ListCustomExtensionsTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'list_custom_extensions';

  @override
  String get description =>
      'Lists all custom VM service extensions registered by the Flutter '
      'app (outside of the built-in Marionette extensions). Each '
      'extension includes its name and an optional description. Use this '
      'to discover what app-specific extensions are available before '
      'calling them with call_custom_extension. '
      'Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations => const ToolAnnotations(
        title: 'List Custom Extensions',
        readOnlyHint: true,
        idempotentHint: true,
      );

  @override
  ToolOutputSchema get outputSchema => ToolOutputSchema(
        properties: {
          'extensions': JsonSchema.array(
            items:
                JsonSchema.object(properties: {}, additionalProperties: true),
          ),
          'count': JsonSchema.integer(),
        },
        required: ['extensions', 'count'],
      );

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    logger.info('Listing custom extensions');
    return runTool(logger, 'list custom extensions', () async {
      final response = await connector.listExtensions();
      final extensions = (response['extensions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      if (extensions.isEmpty) {
        return CallToolResult(
          structuredContent: {'extensions': extensions, 'count': 0},
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
        structuredContent: {
          'extensions': extensions,
          'count': extensions.length,
        },
      );
    });
  }
}

/// MCP tool `call_custom_extension`.
class CallCustomExtensionTool extends BaseTool {
  CallCustomExtensionTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'call_custom_extension';

  @override
  String get description =>
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
      'Requires an active connection established via connect.';

  // Read-only and idempotency hints depend on the target extension.
  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Call Custom Extension');

  @override
  ToolOutputSchema get outputSchema => extensionResponseOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
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
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
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
      return extensionResponseResult(response);
    });
  }
}
