import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/screenshot_scaling.dart';
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
        'platform-view area. Returns the capture as a base64 inline PNG, '
        'downscaled to fit 2000x2000 like take_screenshots; then the result '
        'says by how much, so a point read off the image can be turned into '
        'native x/y. With inline: false saves it into the session directory '
        'instead and returns its path. '
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

/// Handles `native_take_screenshot`: downscales the capture like
/// `take_screenshots` (see [scaleScreenshot]) and returns it inline or —
/// when `args['inline'] == false` — saves it into [session]'s screenshots
/// directory and returns its path. A downscaled capture comes with a note on
/// how image coordinates map to native x/y.
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
    final captured = await context.requireConnector().takeScreenshot();
    if (captured.isEmpty) {
      return CallToolResult(
        content: [
          const TextContent(text: 'Native screenshot was empty'),
        ],
      );
    }
    // A capture that cannot be decoded is passed on unchanged.
    final scaled = scaleScreenshot(captured);
    final pngBase64 = scaled?.pngBase64 ?? captured;
    final note = scaled?.note;
    if (inline) {
      return CallToolResult(
        content: [
          ImageContent(data: pngBase64, mimeType: 'image/png'),
          if (note != null) TextContent(text: note),
        ],
      );
    }
    final path = session!.saveScreenshots([pngBase64]).single;
    return CallToolResult(
      content: [
        TextContent(
          text: 'Saved 1 screenshot(s):\n$path${note == null ? '' : '\n$note'}',
        ),
      ],
    );
  });
}
