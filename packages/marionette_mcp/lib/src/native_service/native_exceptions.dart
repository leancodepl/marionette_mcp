/// Errors raised by the native automation lane.
///
/// Every error carries a [NativeLaneException.message] describing what went
/// wrong and, when there is an obvious remedy, a [NativeLaneException.hint].
/// Both end up in the MCP tool result (via [toString]), so they are written
/// for the agent: say what to do next, not just what failed.
library;

/// Base class of all native-lane errors.
sealed class NativeLaneException implements Exception {
  const NativeLaneException(this.message, {this.hint});

  /// What went wrong.
  final String message;

  /// How to fix it, if known.
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\nHint: $hint';
}

/// A native tool was called without an active session.
final class NativeNotConnectedException extends NativeLaneException {
  const NativeNotConnectedException()
      : super(
          'Not connected to any native connector.',
          hint: 'Call native_connect with platform (android|ios) first.',
        );
}

/// No element in the native UI tree matched the requested target.
final class NativeElementNotFoundException extends NativeLaneException {
  const NativeElementNotFoundException(String target)
      : super(
          'No native element with $target.',
          hint: 'Call native_get_elements and retry with a value from its '
              'output.',
        );
}

/// Preparing the device-side automation server failed.
sealed class NativeBootstrapException extends NativeLaneException {
  const NativeBootstrapException(super.message, {super.hint});
}

/// The stage at which Android native automation bootstrap failed.
enum AndroidBootstrapFailure {
  adbMissing(
    'Install Android SDK Platform Tools and make sure `adb` is on the PATH '
    'of the process running Marionette.',
  ),
  deviceUnavailable(
    'Start an emulator or connect a device and check `adb devices`. Pass '
    'serial to native_connect when several devices are attached.',
  ),
  apkOverrideMissing(
    'Fix the path in MARIONETTE_UIA2_SERVER_APK / MARIONETTE_UIA2_TEST_APK, '
    'or unset both to download the APKs automatically.',
  ),
  download(
    'Check network access to github.com, or download the APKs manually and '
    'set MARIONETTE_UIA2_SERVER_APK and MARIONETTE_UIA2_TEST_APK.',
  ),
  install(
    'Remove stale UIAutomator2 packages (`adb uninstall '
    'io.appium.uiautomator2.server` and `adb uninstall '
    'io.appium.uiautomator2.server.test`) and retry.',
  ),
  instrumentation(
    'Check `adb logcat` for UIAutomator2 errors. Another automation session '
    '(e.g. Appium) on the same device can prevent the server from starting.',
  ),
  portForward(
    'Another process may be using the local port; inspect '
    '`adb forward --list`.',
  ),
  healthCheck(
    'The server started but does not respond. Check `adb logcat` for '
    'UIAutomator2 errors and retry native_connect.',
  );

  const AndroidBootstrapFailure(this.hint);

  /// Default remedy shown to the agent for this stage.
  final String hint;
}

/// A failure while preparing the on-device UIAutomator2 server.
final class AndroidBootstrapException extends NativeBootstrapException {
  AndroidBootstrapException(this.failure, String message, {String? hint})
      : super(message, hint: hint ?? failure.hint);

  final AndroidBootstrapFailure failure;

  @override
  String toString() =>
      'Android native bootstrap failed (${failure.name}): ${super.toString()}';
}

/// The stage at which iOS native automation bootstrap failed.
enum IosBootstrapFailure {
  notMacOS(
    'iOS automation needs macOS with Xcode; run Marionette on a Mac.',
  ),
  simctl(
    'Make sure Xcode command line tools are installed '
    '(`xcode-select --install`) and `xcrun simctl list` works.',
  ),
  noBootedSimulator(
    'Boot a simulator first, e.g. `open -a Simulator` or '
    '`xcrun simctl boot "iPhone 16"`, or pass udid to native_connect.',
  ),
  wdaArtifactsMissing(
    'Build WebDriverAgent once and point MARIONETTE_WDA_XCTESTRUN at the '
    'generated .xctestrun (see README, "Native lane requirements (iOS)").',
  ),
  portConflict(
    'Stop the other WebDriverAgent instance (or the simulator it is attached '
    'to) and retry.',
  ),
  launch(
    'Check that the WebDriverAgent build matches this simulator runtime; '
    'prefer MARIONETTE_WDA_XCTESTRUN over a plain .app bundle.',
  ),
  healthCheck(
    'WebDriverAgent is often slow on first start; retry native_connect. If it '
    'keeps failing, rebuild WDA for this simulator runtime.',
  );

  const IosBootstrapFailure(this.hint);

  /// Default remedy shown to the agent for this stage.
  final String hint;
}

/// A failure while preparing WebDriverAgent on an iOS Simulator.
final class IosBootstrapException extends NativeBootstrapException {
  IosBootstrapException(this.failure, String message, {String? hint})
      : super(message, hint: hint ?? failure.hint);

  final IosBootstrapFailure failure;

  @override
  String toString() =>
      'iOS native bootstrap failed (${failure.name}): ${super.toString()}';
}
