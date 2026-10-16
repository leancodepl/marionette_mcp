import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native-connector connection lifecycle tools.
void registerNativeConnectionTools(
  McpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_connect',
      description:
          'Starts a native automation session (UIAutomator2 on Android, '
          'WebDriverAgent on iOS) for system / native UI that is NOT part of the '
          'Flutter widget tree — permission dialogs, system sheets, and other '
          'surfaces outside Marionette\'s Flutter lane. Independent of the '
          'Flutter "connect" tool; both lanes may be used together. '
          'If the device-side server or session is lost later, it is '
          're-established once automatically: reads are retried, but an '
          'interrupted action is not repeated — the tool then reports that '
          'it may or may not have happened. '
          '$nativeRoutingPreferFlutter '
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
          'Does not affect the Flutter VM-service connection. '
          '$nativeRoutingPreferFlutter',
      annotations: const ToolAnnotations(title: 'Disconnect Native Connector'),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) => handleNativeDisconnect(context),
    );
}

/// Handles `native_connect`. Does not use `runTool` because a failed connect
/// must also leave the context disconnected.
Future<CallToolResult> handleNativeConnect(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final platform = NativePlatform.tryParse(args['platform'] as String?);
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

  try {
    await context.connect(platform, serial: serial, udid: udid);
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully connected native connector '
              '(platform=${platform.name})',
        ),
      ],
    );
  } catch (err) {
    // context.connect disposed the previous session before trying, so the
    // context is already disconnected here.
    logger.severe('Failed to connect native connector', err);
    return CallToolResult(
      isError: true,
      content: [
        TextContent(text: 'Failed to connect native connector: $err'),
      ],
    );
  }
}

/// Handles `native_disconnect`.
Future<CallToolResult> handleNativeDisconnect(
  NativeServiceContext context,
) async {
  final logger = context.logger;
  logger.info('Disconnecting native connector');
  try {
    await context.dispose();
    return CallToolResult(
      content: [
        const TextContent(text: 'Successfully disconnected native connector'),
      ],
    );
  } catch (err) {
    logger.severe('Error during native disconnect', err);
    return CallToolResult(
      isError: true,
      content: [
        TextContent(text: 'Error during native disconnect: $err'),
      ],
    );
  }
}
