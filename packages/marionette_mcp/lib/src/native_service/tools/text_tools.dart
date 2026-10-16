import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/native_service/tools/selector_args.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native text-entry tools.
void registerNativeTextTools(
  McpServer server,
  NativeServiceContext context,
) {
  server.registerTool(
    'native_enter_text',
    description:
        'Types into a native / system text field. Provide text (the string '
        'to type) plus a selector for the field: label (exact visible text), '
        'textContains, id (Android resource-id / iOS accessibility id), type, '
        'optional index — values from native_get_elements. Targets only '
        'native and system text fields — not Flutter TextFields. '
        '$nativeSelectorRules '
        '$nativeRoutingPreferFlutter '
        'Requires native_connect.',
    annotations: const ToolAnnotations(title: 'Native Enter Text'),
    inputSchema: ToolInputSchema(
      properties: {
        'text': JsonSchema.string(
          description: 'The text to type into the native field.',
        ),
        ...nativeSelectorProperties(textKey: 'label'),
      },
      required: ['text'],
    ),
    callback: (args, extra) => handleNativeEnterText(context, args),
  );
}

/// Handles `native_enter_text`.
Future<CallToolResult> handleNativeEnterText(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final input = args['text'] as String?;
  final selector = nativeSelectorFromArgs(args, textKey: 'label');

  if (input == null) {
    return invalidArguments(
      'native_enter_text requires "text" (the string to type).',
    );
  }
  if (selector.isEmpty) {
    return invalidArguments(
      'native_enter_text requires a field selector: label, textContains, id '
      'or type.',
    );
  }

  logger.info('Native enter text target ${selector.describe()}');
  return runTool(logger, 'native enter text', () async {
    final connector = context.requireConnector();
    final match = selectElement(await connector.getNativeElements(), selector);
    await connector.enterText(match, input);
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully entered text into native field '
              '${selector.describe()}',
        ),
      ],
    );
  });
}
