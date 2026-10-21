/// Device operations of the native lane that do not go through the
/// WebDriver session: the notification shade. Backed by `adb` (Android).
/// See docs/native-lane-decisions.md#d12.
library;

/// Device operations outside the WebDriver session (D12).
///
/// Failures are reported as `NativeLaneException`s with a hint; operations
/// a platform cannot do throw `NativeUnsupportedException`.
abstract interface class NativeDevice {
  /// Opens the notification shade. Throws `NativeUnsupportedException` when
  /// the platform needs a gesture instead (iOS).
  Future<void> openNotifications();

  /// Closes the notification shade (see [openNotifications]).
  Future<void> closeNotifications();
}
