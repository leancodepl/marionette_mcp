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
        'to type) and either a selector for the field — label (exact visible '
        'text), textContains, id, type, optional index; values from '
        'native_get_elements — or no selector to type into the field that '
        'currently has keyboard focus (e.g. after native_tap on it). Typing '
        'into the focused field also works for Flutter fields when the '
        'software keyboard is not visible to native_get_elements (Android). '
        'Set clear to empty the field first. '
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
        'clear': JsonSchema.boolean(
          description: 'Empty the field before typing (default false).',
        ),
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
  final clear = args['clear'] == true;

  if (input == null) {
    return invalidArguments(
      'native_enter_text requires "text" (the string to type).',
    );
  }
  if (selector.isEmpty && selector.index != null) {
    return invalidArguments('native_enter_text index requires a selector.');
  }

  final target =
      selector.isEmpty ? 'the focused field' : 'field ${selector.describe()}';
  logger.info('Native enter text into $target (clear=$clear)');
  return runTool(logger, 'native enter text', () async {
    final connector = context.requireConnector();
    if (selector.isEmpty) {
      await connector.typeText(input, clear: clear);
    } else {
      final match =
          selectElement(await connector.getNativeElements(), selector);
      await connector.enterText(match, input, clear: clear);
    }
    return CallToolResult(
      content: [TextContent(text: 'Successfully entered text into $target')],
    );
  });
}
