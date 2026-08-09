import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers MCP tools that change the device configuration the app runs
/// under: `set_device_config`.
void registerDeviceTools(
  McpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server.registerTool(
    'set_device_config',
    description:
        'Overrides the device configuration the running app sees — text scale, bold text, and light/dark appearance — without touching the real device settings. Use it to sweep a screen under accessibility or appearance conditions (large text, bold text, dark mode). Omitted parameters keep their current override; reset clears every override, and combining reset with values leaves exactly those values set (that is how a single override is reverted). Requires the app to wrap its root widget in MarionetteDeviceConfig — if it does not, this returns setup instructions. Requires an active connection established via connect.',
    annotations: const ToolAnnotations(title: 'Set Device Config'),
    inputSchema: ToolInputSchema(
      properties: {
        'text_scale': JsonSchema.number(
          description:
              'Linear text scale, as a multiplier of the platform default. '
              'Must be greater than 0. Typical sweep values are 1.0 '
              '(default), 1.5 (large) and 2.0 (very large); real devices top '
              'out around 3.0, and much larger values mostly produce overflow '
              'errors rather than useful signal. Note that some Material '
              'widgets clamp their own text scaling.',
        ),
        'bold_text': JsonSchema.boolean(
          description: 'The system bold-text accessibility setting.',
        ),
        'platform_brightness': JsonSchema.string(
          description:
              'The system light/dark appearance. Drives MaterialApp theme '
              'resolution when themeMode is system.',
          enumValues: supportedBrightnessValues.toList(),
        ),
        'reset': JsonSchema.boolean(
          description:
              'Clear every override and revert to the platform defaults. '
              'Applied before any other parameter in the same call.',
        ),
      },
    ),
    callback: (args, extra) => setDeviceConfig(connector, logger, args),
  );
}

/// Handles a `set_device_config` invocation: validates the args and forwards
/// them to [connector].
///
/// Extracted from the tool callback so the validation branches can be
/// exercised in isolation.
Future<CallToolResult> setDeviceConfig(
  VmServiceConnector connector,
  logging.Logger logger,
  Map<String, dynamic> args,
) {
  final rawTextScale = args['text_scale'] as num?;
  final boldText = args['bold_text'] as bool?;
  final brightness = args['platform_brightness'] as String?;
  final reset = args['reset'] == true;

  final setsAnyField =
      rawTextScale != null || boldText != null || brightness != null;

  // A bare `reset: false` would otherwise report success having changed
  // nothing.
  if (!setsAnyField && !reset) {
    return _invalid(
      'At least one parameter is required: text_scale, bold_text, '
      'platform_brightness, or reset=true.',
    );
  }

  if (rawTextScale != null && rawTextScale <= 0) {
    return _invalid('text_scale must be greater than 0.');
  }

  if (invalidBrightnessError(brightness) case final error?) {
    return _invalid(error);
  }

  logger.info(
    'Setting device config: textScale=$rawTextScale, boldText=$boldText, '
    'platformBrightness=$brightness, reset=$reset',
  );

  return runTool(logger, 'set device config', () async {
    final response = await connector.setDeviceConfig(
      textScale: rawTextScale?.toDouble(),
      boldText: boldText,
      platformBrightness: brightness,
      reset: reset,
    );
    final message = response['message'] as String?;
    return CallToolResult(
      content: [TextContent(text: message ?? 'Device config updated')],
    );
  });
}

Future<CallToolResult> _invalid(String message) async => CallToolResult(
      isError: true,
      content: [TextContent(text: message)],
    );
