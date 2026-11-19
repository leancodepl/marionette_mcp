import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/poll.dart';

/// [NativeDevice] for an iOS Simulator. iOS has no command for the
/// Notification Center, so it is driven by edge swipes through the
/// connector.
final class IosNativeDevice implements NativeDevice {
  IosNativeDevice(this._connector);

  final NativeConnector _connector;

  /// Opens the Notification Center and, from the home screen, checks that
  /// it did: a swipe while a banner is on screen can miss (seen on iOS
  /// 26.4). Over an app the Notification Center is not in the tree, so
  /// there is nothing to check.
  @override
  Future<void> openNotifications() async {
    final fromHome = await _connector.foregroundApp == _springboard;
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      await _swipeOpen();
      if (!fromHome || await _waitForNotificationCenter()) return;
    }
    throw const NativeOperationFailedException(
      'The Notification Center did not open.',
      hint: 'A banner on screen can take the swipe: wait until it is gone, '
          'then retry.',
    );
  }

  /// Swipes up from the bottom edge: a swipe in the middle only scrolls the
  /// notification list.
  @override
  Future<void> closeNotifications() async {
    final screen = await _connector.getScreen();
    final x = screen.width ~/ 2;
    await _connector.swipe(
      startX: x,
      startY: screen.height - 1,
      endX: x,
      endY: screen.height ~/ 2,
    );
  }

  /// Swipes down from the top edge, left of center: the top right opens
  /// Control Center.
  Future<void> _swipeOpen() async {
    final screen = await _connector.getScreen();
    final x = screen.width ~/ 3;
    await _connector.swipe(
      startX: x,
      startY: 1,
      endX: x,
      endY: (screen.height * _openSwipeShare).round(),
    );
  }

  /// Whether the Notification Center window shows up within a few reads.
  Future<bool> _waitForNotificationCenter() => pollUntil(
        () async => (await _connector.getNativeElements())
            .any((e) => e.resourceId == _notificationCenterWindow),
        attempts: _openChecks,
        interval: _openCheckInterval,
      );
}

const _springboard = 'com.apple.springboard';

/// Window of the Notification Center, in the tree only while it is open.
const _notificationCenterWindow = 'SBCoverSheetWindow';

const _openAttempts = 2;
const _openChecks = 3;
const _openCheckInterval = Duration(milliseconds: 300);

/// Share of the screen height the opening swipe covers.
const _openSwipeShare = 0.6;
