import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/supported_platform.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/native_service/web_native_connector.dart';
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
      description: 'Starts a native automation session (UIAutomator2 on Android, '
          'WebDriverAgent on iOS, ChromeDriver on web) for system / native / '
          'browser DOM UI that is NOT part of the Flutter widget tree — '
          'permission dialogs, system sheets, HTML around a Flutter web app, '
          'and other surfaces outside Marionette\'s Flutter lane. Independent '
          'of the Flutter "connect" tool; both lanes may be used together. '
          '$nativeRoutingPreferFlutter '
          'Requires platform=android|ios|web; optionally pass serial (Android), '
          'udid (iOS simulator), debuggerAddress / chromeDriverUrl (web). '
          'On web, native_connect attaches to the Chrome from flutter run '
          '(via debuggerAddress, MARIONETTE_CHROME_DEBUGGER_ADDRESS, or '
          'auto-discovery).',
      annotations: const ToolAnnotations(title: 'Connect Native Connector'),
      inputSchema: ToolInputSchema(
        properties: {
          'platform': JsonSchema.string(
            description: 'Target platform: "android" (UIAutomator2), "ios" '
                '(WebDriverAgent on simulator), or "web" (ChromeDriver).',
          ),
          'serial': JsonSchema.string(
            description: 'Optional Android device serial (adb -s). When omitted, '
                'uses the default adb device.',
          ),
          'udid': JsonSchema.string(
            description: 'Optional iOS Simulator UDID. When omitted, uses the '
                'booted simulator.',
          ),
          'debuggerAddress': JsonSchema.string(
            description: 'Chrome DevTools address (e.g. "127.0.0.1:9222") to '
                'attach to an already-running browser — typically the Chrome '
                'from flutter run -d chrome --web-browser-debug-port=9222. '
                'When omitted, Marionette tries MARIONETTE_CHROME_DEBUGGER_ADDRESS '
                'then auto-discovery. Used only when platform=web.',
          ),
          'chromeDriverUrl': JsonSchema.string(
            description: 'Optional ChromeDriver base URL when already running '
                '(attach mode). When omitted, Marionette starts chromedriver '
                'from PATH / MARIONETTE_CHROMEDRIVER. Used only when '
                'platform=web.',
          ),
        },
        required: ['platform'],
      ),
      callback: (args, extra) async {
        final platform = SupportedPlatform.tryParse(args['platform'] as String?);
        final serial = args['serial'] as String?;
        final udid = args['udid'] as String?;
        final chromeDriverUrl = args['chromeDriverUrl'] as String?;
        final debuggerAddress = args['debuggerAddress'] as String?;

        if (platform == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'native_connect requires platform to be '
                    '${SupportedPlatform.quotedWireNames}.',
              ),
            ],
          );
        }

        logger.info(
          'Connecting native connector: platform=${platform.wireName} '
          'serial=$serial udid=$udid debuggerAddress=$debuggerAddress '
          'chromeDriverUrl=$chromeDriverUrl',
        );

        try {
          await context.dispose();

          final NativeConnector connector;
          switch (platform) {
            case SupportedPlatform.android:
              connector = await AndroidNativeConnector.connect(serial: serial);
            case SupportedPlatform.ios:
              connector = await IosNativeConnector.connect(udid: udid);
            case SupportedPlatform.web:
              connector = await WebNativeConnector.connect(
                chromeDriverUrl: chromeDriverUrl,
                debuggerAddress: debuggerAddress,
              );
          }
          context.connector = connector;

          return CallToolResult(
            content: [
              TextContent(
                text: 'Successfully connected native connector '
                    '(platform=${platform.wireName})',
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
      description: 'Stops the native automation session started by native_connect '
          'and releases device-side processes (UIAutomator2 / WDA / ChromeDriver). '
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
