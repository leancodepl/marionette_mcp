import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';

/// [NativeDevice] for an iOS Simulator. It has no command for the
/// Notification Center; `native_notifications` swipes instead.
final class IosNativeDevice implements NativeDevice {
  const IosNativeDevice();

  static const _notificationGestureHint =
      'The tool opens and closes the Notification Center with a swipe.';

  @override
  Future<void> openNotifications() => throw const NativeUnsupportedException(
        'iOS has no command to open the Notification Center.',
        hint: _notificationGestureHint,
      );

  @override
  Future<void> closeNotifications() => throw const NativeUnsupportedException(
        'iOS has no command to close the Notification Center.',
        hint: _notificationGestureHint,
      );
}
