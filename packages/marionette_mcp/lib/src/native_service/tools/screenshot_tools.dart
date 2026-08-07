import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/screenshot_saver.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native screenshot tools.
void registerNativeScreenshotTools(
  McpServer server,
  NativeServiceContext context,
  logging.Logger logger,
) {
  server.registerTool(
    'native_take_screenshot',
    description: 'Takes a PNG screenshot of the full device screen via the native '
        'automation session (UIAutomator2 / WebDriverAgent / ChromeDriver). '
        'Unlike Flutter take_screenshots, this captures content outside the '
        'Flutter widget tree — embedded WebViews (e.g. webview_flutter pages), '
        'system surfaces on top of the app (permission dialogs, sheets, '
        'status-bar panels), and on web, browser DOM outside Flutter CanvasKit. '
        'Use it when native_get_elements shows WebView or system UI you want '
        'to visually inspect, or when Flutter take_screenshots shows a blank '
        'platform-view area. By default returns the capture as a base64 inline '
        'PNG (no file written). When MARIONETTE_SCREENSHOTS_DIR is set, also '
        'saves the PNG to that directory and includes the absolute path '
        'alongside the inline image. When a path is returned, embed it as a '
        'markdown image so the user can see it. '
        '$nativeRoutingPreferFlutter '
        'Requires native_connect.',
    annotations: const ToolAnnotations(
      title: 'Native Take Screenshot',
      readOnlyHint: true,
    ),
    inputSchema: const ToolInputSchema(properties: {}),
    callback: (args, extra) async {
      logger.info('Taking native screenshot');
      return runTool(logger, 'native take screenshot', () async {
        final connector = context.requireConnector();
        final pngBase64 = await connector.takeScreenshot();
        if (pngBase64.isEmpty) {
          return CallToolResult(
            content: [
              const TextContent(text: 'Native screenshot was empty'),
            ],
          );
        }
        final saved = saveScreenshotPng(pngBase64, suffix: 'native');
        if (saved != null) {
          logger.info('Saved native screenshot to ${saved.path}');
        }
        return CallToolResult(
          content: screenshotToolContent(
            pngBase64: pngBase64,
            savedFile: saved,
          ),
        );
      });
    },
  );
}
