import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native-connector connection lifecycle tools.
void registerNativeConnectionTools(
  McpServer server,
  NativeServiceContext context,
  logging.Logger logger,
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
      callback: (args, extra) async {
        final platform = (args['platform'] as String?)?.toLowerCase().trim();
        final serial = args['serial'] as String?;
        final udid = args['udid'] as String?;

        if (platform != 'android' && platform != 'ios') {
          return CallToolResult(
            isError: true,
            content: [
              const TextContent(
                text: 'native_connect requires platform to be '
                    '"android" or "ios".',
              ),
            ],
          );
        }

        logger.info(
          'Connecting native connector: platform=$platform '
          'serial=$serial udid=$udid',
        );

        try {
          await context.dispose();

          final NativeConnector connector;
          if (platform == 'android') {
            connector = await AndroidNativeConnector.connect(serial: serial);
          } else {
            connector = await IosNativeConnector.connect(udid: udid);
          }
          context.connector = connector;

          return CallToolResult(
            content: [
              TextContent(
                text: 'Successfully connected native connector '
                    '(platform=$platform)',
              ),
            ],
          );
        } catch (err) {
          logger.severe('Failed to connect native connector', err);
          context.connector = null;
          return CallToolResult(
            isError: true,
            content: [
              TextContent(text: 'Failed to connect native connector: $err'),
            ],
          );
        }
      },
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
      callback: (args, extra) async {
        logger.info('Disconnecting native connector');
        try {
          await context.dispose();
          return CallToolResult(
            content: [
              const TextContent(
                text: 'Successfully disconnected native connector',
              ),
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
      },
    );
}
