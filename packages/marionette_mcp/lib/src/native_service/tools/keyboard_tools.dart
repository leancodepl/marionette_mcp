import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';

/// Registers native key and software-keyboard tools.
void registerNativeKeyboardTools(
  LoggedMcpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_press_key',
      description: 'Presses a system or hardware key on the device: '
          '${NativeKey.values.map((k) => k.wireName).join(', ')}. enter, tab '
          'and backspace act on the focused field (also Flutter fields), '
          'like the software keyboard. back, recents and tab exist only on '
          'Android; on iOS the call fails with a hint. For key presses inside '
          'a Flutter app prefer the Flutter press_key tool. '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Press Key'),
      inputSchema: ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'Key to press. '
                '${NativeKey.values.map((k) => '${k.wireName}: ${k.summary}').join(' ')}',
          ),
        },
        required: ['key'],
      ),
      callback: (args, extra) => handleNativePressKey(context, args),
    )
    ..registerTool(
      'native_hide_keyboard',
      description:
          'Hides the software keyboard if it is shown, so that UI it covers '
          '(e.g. a bottom navigation bar) is reachable again. Reports whether '
          'the keyboard was shown. Android: presses Back only while the '
          'keyboard is shown (never navigates). iOS: uses the keyboard\'s '
          'Done / dismiss key; keyboards without one (e.g. number pad) fail '
          'with a hint. '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(
        title: 'Native Hide Keyboard',
        idempotentHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) => handleNativeHideKeyboard(context),
    );
}

/// Handles `native_press_key`.
Future<CallToolResult> handleNativePressKey(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final key = NativeKey.tryParse(args['key'] as String?);
  if (key == null) {
    return invalidArguments(
      'native_press_key requires key to be one of: '
      '${NativeKey.values.map((k) => k.wireName).join(', ')}.',
    );
  }

  logger.info('Native pressing key ${key.wireName}');
  return runTool(logger, 'native press key', () async {
    await context.requireConnector().pressKey(key);
    return CallToolResult(
      content: [TextContent(text: 'Pressed ${key.wireName}')],
    );
  });
}

/// Handles `native_hide_keyboard`.
Future<CallToolResult> handleNativeHideKeyboard(
  NativeServiceContext context,
) {
  final logger = context.logger;
  logger.info('Native hiding keyboard');
  return runTool(logger, 'native hide keyboard', () async {
    final wasShown = await context.requireConnector().hideKeyboard();
    return CallToolResult(
      content: [
        TextContent(
          text: wasShown ? 'Keyboard hidden' : 'Keyboard was not shown',
        ),
      ],
    );
  });
}
