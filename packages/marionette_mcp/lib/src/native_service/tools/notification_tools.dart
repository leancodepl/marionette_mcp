import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';

/// Actions of `native_notifications`.
enum NativeNotificationsAction {
  open,
  close;

  static NativeNotificationsAction? tryParse(Object? raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

/// Registers `native_notifications`, which opens and closes the system
/// notification list.
void registerNativeNotificationTools(
  LoggedMcpServer server,
  NativeServiceContext context,
) {
  server.registerTool(
    'native_notifications',
    description: 'open / close the notification shade (Android) or '
        'Notification Center (iOS, by swipe). Read the notifications with '
        'native_get_elements while the shade is open. To open a notification, '
        'native_tap it (Android). In the iOS Notification Center the first '
        'tap on a group of one app\'s notifications expands it; if only '
        '"N Notifications" is listed, tap it first to expand the list. A tap '
        'does not open a notification — swipe it right across its full '
        'width (native_swipe at its vertical center). Opened over the app, '
        'the Notification Center is not in the tree: send the app to the '
        'background (native_press_key key=home) first. Open it after a '
        'banner is gone: a banner on screen can take the opening swipe. '
        'Requires native_connect.',
    annotations: const ToolAnnotations(title: 'Native Notifications'),
    inputSchema: ToolInputSchema(
      properties: {
        'action': JsonSchema.string(description: '"open" or "close".'),
      },
      required: ['action'],
    ),
    callback: (args, extra) => handleNativeNotifications(context, args),
  );
}

CallToolResult _text(String text) =>
    CallToolResult(content: [TextContent(text: text)]);

/// Handles `native_notifications`.
Future<CallToolResult> handleNativeNotifications(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final action = NativeNotificationsAction.tryParse(args['action']);
  if (action == null) {
    return invalidArguments(
      'native_notifications action must be "open" or "close".',
    );
  }

  final logger = context.logger;
  logger.info('Native notifications ${action.name}');
  return runNativeTool(logger, 'native notifications', () async {
    final connector = context.requireConnector();
    switch (action) {
      case NativeNotificationsAction.open:
        await connector.device.openNotifications();
        return _text('Opened the notifications. Read them with '
            'native_get_elements; close with action=close.');
      case NativeNotificationsAction.close:
        await connector.device.closeNotifications();
        return _text('Closed the notifications.');
    }
  });
}
