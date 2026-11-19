/// Device operations of the native lane: the notification shade. Android
/// runs `adb` commands; iOS swipes through its connector.
library;

/// Device operations of the native lane.
///
/// Failures are reported as `NativeLaneException`s with a hint.
abstract interface class NativeDevice {
  /// Opens the notification shade (Android, with `cmd statusbar`) or the
  /// Notification Center (iOS, with a swipe from the top edge). Throws
  /// `NativeOperationFailedException` when it did not open; iOS checks this
  /// only from the home screen.
  Future<void> openNotifications();

  /// Closes the notification shade (see [openNotifications]).
  Future<void> closeNotifications();
}
