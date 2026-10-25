import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'base_tool.dart';
import 'tool_results.dart';

/// MCP tool `press_key`.
class PressKeyTool extends BaseTool {
  PressKeyTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'press_key';

  @override
  String get description =>
      'Presses a keyboard key in the Flutter app, producing a real key event '
      'that flows through the focus system — unlike enter_text, which only '
      'replaces a field\'s value. Use it to submit a form (enter), move focus '
      '(tab), dismiss a dialog (escape), edit within a field (backspace, '
      'delete, arrowLeft/arrowRight/arrowUp/arrowDown, home, end), or trigger '
      'app shortcuts via modifiers (for example control+a to select all). '
      'The key is sent to whatever currently has focus, exactly like a real '
      'keyboard, so focus a target first if needed (for example with tap). '
      'Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations => const ToolAnnotations(title: 'Press Key');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The key to press. Named keys: enter, tab, escape, backspace, '
                'delete, space, arrowUp, arrowDown, arrowLeft, arrowRight, home, '
                'end, pageUp, pageDown. Also accepts a single character a-z or '
                '0-9 (case-insensitive).',
          ),
          'modifiers': JsonSchema.string(
            description:
                'Optional comma-separated modifier keys to hold during the '
                'press: any of control, shift, alt, meta (e.g. "control" or '
                '"control,shift"). On macOS use meta for the Command key.',
          ),
        },
        required: ['key'],
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final key = args['key'] as String;
    final modifiers = args['modifiers'] as String?;

    final modifierError = invalidModifiersError(modifiers);
    if (modifierError != null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: modifierError)],
      );
    }

    logger.info('Pressing key: $key (modifiers: ${modifiers ?? 'none'})');
    return runTool(logger, 'press key', () async {
      final response = await connector.pressKey(key, modifiers: modifiers);
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully pressed key');
    });
  }
}
