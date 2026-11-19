import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native-connector connection lifecycle tools.
void registerNativeConnectionTools(
  LoggedMcpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_connect',
      description:
          'The native_* tools are for UI outside the Flutter widget tree; '
          'Flutter tools stay first for in-app widgets, and native screen '
          'pixels never mix with Flutter logical coordinates. '
          'Starts a native automation session (UIAutomator2 on Android, '
          'WebDriverAgent on iOS) for permission dialogs, system sheets and '
          'other system UI. Independent of the Flutter "connect" tool; both '
          'lanes may be used together. '
          'Call it before the flow opens system UI: starting WebDriverAgent '
          'can dismiss an alert already on screen. If a native call later '
          'says the device-side server or session is gone, call it again. '
          'Requires platform=android|ios; optionally pass serial (Android) or '
          'udid (iOS simulator).',
      annotations: const ToolAnnotations(title: 'Connect Native Connector'),
      inputSchema: ToolInputSchema(
        properties: {
          'platform': JsonSchema.string(
            description: 'Target platform: "android" (UIAutomator2) or "ios" '
                '(WebDriverAgent on simulator).',
          ),
          'serial': JsonSchema.string(
            description:
                'Optional Android device serial (adb -s). When omitted, '
                'uses the default adb device.',
          ),
          'udid': JsonSchema.string(
            description: 'Optional iOS Simulator UDID. When omitted, uses the '
                'booted simulator.',
          ),
        },
        required: ['platform'],
      ),
      callback: (args, extra) => handleNativeConnect(context, args),
    )
    ..registerTool(
      'native_disconnect',
      description:
          'Stops the native automation session started by native_connect '
          'and releases device-side processes (UIAutomator2 / WDA). '
          'Does not affect the Flutter VM-service connection.',
      annotations: const ToolAnnotations(title: 'Disconnect Native Connector'),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) => handleNativeDisconnect(context),
    );
}

/// Handles `native_connect`.
Future<CallToolResult> handleNativeConnect(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final platform = enumArg(args, 'platform', NativePlatform.values);
  final serial = args['serial'] as String?;
  final udid = args['udid'] as String?;

  if (platform == null) {
    return invalidArguments(
      'native_connect requires platform to be "android" or "ios".',
    );
  }

  logger.info(
    'Connecting native connector: platform=${platform.name} '
    'serial=$serial udid=$udid',
  );
  return runTool(logger, 'connect native connector', () async {
    await context.connect(platform, serial: serial, udid: udid);
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully connected native connector '
              '(platform=${platform.name})',
        ),
      ],
    );
  });
}

/// Handles `native_disconnect`.
Future<CallToolResult> handleNativeDisconnect(NativeServiceContext context) {
  final logger = context.logger;
  logger.info('Disconnecting native connector');
  return runTool(logger, 'disconnect native connector', () async {
    await context.dispose();
    return CallToolResult(
      content: [
        const TextContent(text: 'Successfully disconnected native connector'),
      ],
    );
  });
}
