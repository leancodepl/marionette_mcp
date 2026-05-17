import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/permissions/permission_accepter.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers MCP tools that drive OS-level dialogs that sit outside the
/// Flutter widget tree: `accept_permission`.
void registerPermissionTools(
  McpServer server,
  logging.Logger logger, {
  PermissionAccepter? accepter,
}) {
  final permissionAccepter = accepter ?? PermissionAccepter();

  server.registerTool(
    'accept_permission',
    description: 'Accepts a native OS permission dialog (location, camera, '
        'notifications, etc.) that is overlaying the Flutter app. Permission '
        'dialogs are rendered by the OS and live outside the Flutter widget '
        'tree, so they cannot be tapped via the regular `tap` tool. Use this '
        'when `take_screenshots` shows such a dialog blocking the app. Under '
        'the hood: on Android uses `adb shell uiautomator dump` to find the '
        'allow button, then `adb shell input tap`; on iOS Simulator drives '
        'the Simulator app via AppleScript. Requires exactly one connected '
        'Android device OR one booted iOS simulator on the host machine. '
        'Does not require an active `connect` session.',
    annotations: const ToolAnnotations(title: 'Accept Permission Dialog'),
    inputSchema: const ToolInputSchema(properties: {}),
    callback: (args, extra) async {
      logger.info('Accepting permission dialog');
      try {
        final result = await permissionAccepter.accept();
        return CallToolResult(
          isError: !result.success,
          content: [TextContent(text: result.message)],
        );
      } catch (err) {
        logger.warning('Failed to accept permission', err);
        return CallToolResult(
          isError: true,
          content: [TextContent(text: 'Failed to accept permission: $err')],
        );
      }
    },
  );
}
