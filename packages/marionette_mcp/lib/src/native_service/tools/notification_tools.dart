import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
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
        'native_tap it. In the iOS Notification Center the first tap on a '
        'group of one app\'s notifications expands it; a tap on a single '
        'notification may only slide it aside and show an "Open" button — '
        'native_wait_for text="Open", then native_tap it. Requires '
        'native_connect.',
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
  return runTool(logger, 'native notifications', () async {
    final connector = context.requireConnector();
    final ios = context.platform == NativePlatform.ios;
    switch (action) {
      case NativeNotificationsAction.open:
        if (ios) {
          await _swipeNotificationCenter(connector, open: true);
        } else {
          await connector.device.openNotifications();
        }
        // In the iOS Notification Center a tap on a group expands it, and a
        // tap on a notification may only slide it aside to show "Open"
        // (seen on the Simulator).
        return _text('Opened the notifications. Read them with '
            'native_get_elements; close with action=close.'
            '${ios ? ' Notifications of one app are grouped: the first tap '
                'on a group expands it. If a tap on a notification only '
                'slides it aside, native_wait_for text="Open" and native_tap '
                'it. If only "N Notifications" is listed, tap it first to '
                'expand the list. Opened over the app, the Notification '
                'Center is not in the tree: send the app to the background '
                '(native_press_key key=home) first.' : ''}');
      case NativeNotificationsAction.close:
        if (ios) {
          await _swipeNotificationCenter(connector, open: false);
        } else {
          await connector.device.closeNotifications();
        }
        return _text('Closed the notifications.');
    }
  });
}

/// iOS has no command for the Notification Center: swipe down from the
/// top edge (left of center — the top right opens Control Center), or up
/// from the lower part of the screen to close it.
Future<void> _swipeNotificationCenter(
  NativeConnector connector, {
  required bool open,
}) async {
  final screen = await connector.getScreen();
  final x = screen.width ~/ 3;
  if (open) {
    await connector.swipe(
      startX: x,
      startY: 1,
      endX: x,
      endY: (screen.height * 0.6).round(),
    );
  } else {
    await connector.swipe(
      startX: screen.width ~/ 2,
      startY: screen.height - 1,
      endX: screen.width ~/ 2,
      endY: screen.height ~/ 2,
    );
  }
}
