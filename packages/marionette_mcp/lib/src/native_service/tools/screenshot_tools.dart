import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native screenshot tools.
void registerNativeScreenshotTools(
  LoggedMcpServer server,
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
        'platform-view area. Returns the capture as a base64 inline PNG; '
        'with inline: false saves it into the session directory instead and '
        'returns its path. '
        '$nativeRoutingPreferFlutter '
        'Requires native_connect.',
    annotations: const ToolAnnotations(
      title: 'Native Take Screenshot',
      readOnlyHint: true,
    ),
    inputSchema: ToolInputSchema(
      properties: {
        'inline': JsonSchema.boolean(
          description: 'If false, saves the screenshot into the session '
              'directory and returns its path instead of the image data. '
              'Defaults to true.',
        ),
      },
    ),
    callback: (args, extra) => handleNativeTakeScreenshot(
      context,
      session: server.stepLogger.session,
      args: args,
    ),
  );
}

/// Handles `native_take_screenshot`: returns the capture inline or — when
/// `args['inline'] == false` — saves it into [session]'s screenshots
/// directory and returns its path, as `take_screenshots` does.
Future<CallToolResult> handleNativeTakeScreenshot(
  NativeServiceContext context, {
  Session? session,
  Map<String, dynamic> args = const {},
}) async {
  final logger = context.logger;
  final inline = args['inline'] != false;
  if (!inline && session == null) {
    return CallToolResult(
      isError: true,
      content: [
        const TextContent(
          text: 'inline: false requires an active session, which is only '
              'created once the Flutter connect succeeds and only when the '
              'app enables session reports '
              '(MarionetteConfiguration.enableSessionReports).',
        ),
      ],
    );
  }

  logger.info('Taking native screenshot');
  return runTool(logger, 'native take screenshot', () async {
    final pngBase64 = await context.requireConnector().takeScreenshot();
    if (pngBase64.isEmpty) {
      return CallToolResult(
        content: [
          const TextContent(text: 'Native screenshot was empty'),
        ],
      );
    }
    if (inline) {
      return CallToolResult(
        content: [ImageContent(data: pngBase64, mimeType: 'image/png')],
      );
    }
    final path = session!.saveScreenshots([pngBase64]).single;
    return CallToolResult(
      content: [TextContent(text: 'Saved 1 screenshot(s):\n$path')],
    );
  });
}
