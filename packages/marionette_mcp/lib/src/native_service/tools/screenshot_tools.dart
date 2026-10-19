import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/native_service/tools/selector_args.dart';
import 'package:marionette_mcp/src/screenshot_saver.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native screenshot tools.
void registerNativeScreenshotTools(
  McpServer server,
  NativeServiceContext context,
) {
  server.registerTool(
    'native_take_screenshot',
    description:
        'Takes a PNG screenshot of the full device screen via the native '
        'automation session (UIAutomator2 / WebDriverAgent). '
        'Unlike Flutter take_screenshots, this captures content outside the '
        'Flutter widget tree — embedded WebViews (e.g. webview_flutter pages) '
        'and system surfaces on top of the app (permission dialogs, sheets, '
        'status-bar panels). '
        'Use it when native_get_elements shows WebView or system UI you want '
        'to visually inspect, or when Flutter take_screenshots shows a blank '
        'platform-view area. With a selector (text, textContains, id, type, '
        'optional index — values from native_get_elements) captures just '
        'that element, e.g. to check a WebView or an icon closely. By '
        'default returns the capture as a base64 inline '
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
    inputSchema: ToolInputSchema(properties: nativeSelectorProperties()),
    callback: (args, extra) => handleNativeTakeScreenshot(context, args),
  );
}

/// Handles `native_take_screenshot`.
Future<CallToolResult> handleNativeTakeScreenshot(
  NativeServiceContext context, [
  Map<String, dynamic> args = const {},
]) async {
  final logger = context.logger;
  final selector = nativeSelectorFromArgs(args);
  if (selector.isEmpty && selector.index != null) {
    return invalidArguments(
      'native_take_screenshot index requires a selector.',
    );
  }

  logger.info(selector.isEmpty
      ? 'Taking native screenshot'
      : 'Taking native screenshot of ${selector.describe()}');
  return runTool(logger, 'native take screenshot', () async {
    final connector = context.requireConnector();
    final pngBase64 = selector.isEmpty
        ? await connector.takeScreenshot()
        : await connector.takeElementScreenshot(
            selectElement(await connector.getNativeElements(), selector),
          );
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
}
