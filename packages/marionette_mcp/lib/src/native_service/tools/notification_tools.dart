import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
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
        'native_tap it (Android). In the iOS Notification Center the first '
        'tap on a group of one app\'s notifications expands it; a tap does '
        'not open a notification — swipe it right across its full width '
        '(native_swipe at its vertical center). Open it after a banner is '
        'gone: a banner on screen can take the opening swipe. Requires '
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
          await _openNotificationCenter(connector);
        } else {
          await connector.device.openNotifications();
        }
        // In the iOS Notification Center a tap on a group expands it, and a
        // tap on a notification may only slide it aside to show an "Open"
        // that slides back within seconds; a swipe right opens it (seen on
        // iOS 18.6 and 26.4).
        return _text('Opened the notifications. Read them with '
            'native_get_elements; close with action=close.'
            '${ios ? ' Notifications of one app are grouped: the first tap '
                'on a group expands it. Open a notification by swiping it '
                'right across its full width (native_swipe at its vertical '
                'center). '
                'If only "N Notifications" is listed, tap it first to '
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

/// Opens the iOS Notification Center and, from the home screen, checks that
/// it did: a swipe while a banner is on screen can miss (seen on iOS
/// 26.4). Over an app the Notification Center is not in the tree, so there
/// is nothing to check.
Future<void> _openNotificationCenter(NativeConnector connector) async {
  final fromHome = await connector.foregroundApp == _springboard;
  for (var attempt = 0; attempt < 2; attempt++) {
    await _swipeNotificationCenter(connector, open: true);
    if (!fromHome) return;
    for (var check = 0; check < 3; check++) {
      final elements = await connector.getNativeElements();
      if (elements.any((e) => e.resourceId == _notificationCenterWindow)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  throw const NativeOperationFailedException(
    'The Notification Center did not open.',
    hint: 'A banner on screen can take the swipe: wait until it is gone, '
        'then retry.',
  );
}

const _springboard = 'com.apple.springboard';

/// Window of the Notification Center, in the tree only while it is open.
const _notificationCenterWindow = 'SBCoverSheetWindow';

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
