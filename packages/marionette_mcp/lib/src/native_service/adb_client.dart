import 'dart:io';

import 'package:marionette_mcp/src/native_service/process.dart';

/// Thin wrapper over the `adb` CLI bound to one device.
///
/// Every command goes through [run], which prepends `-s <serial>` when
/// [serial] is set, so callers never assemble device selection themselves.
class AdbClient {
  AdbClient({this.serial, ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  /// Device serial passed as `adb -s`, or null for the default device.
  final String? serial;

  final ProcessRunner _run;

  /// Returns [arguments] prefixed with the device selection flags.
  List<String> argumentsFor(List<String> arguments) => [
        if (serial != null) ...['-s', serial!],
        ...arguments,
      ];

  /// Runs `adb <arguments>` against this device.
  ///
  /// Throws [ProcessException] when `adb` cannot be started (e.g. not on
  /// PATH); a non-zero exit code is returned, not thrown.
  Future<ProcessResult> run(List<String> arguments) =>
      _run('adb', argumentsFor(arguments));

  /// Runs `adb shell <arguments>` against this device.
  Future<ProcessResult> shell(List<String> arguments) =>
      run(['shell', ...arguments]);

  /// Package that owns the focused window (a system dialog when one covers
  /// the app), or null when it cannot be determined. Never throws.
  ///
  /// Android 10+ reports focus under `dumpsys window displays`; older
  /// versions only under `dumpsys window windows`, which newer versions no
  /// longer include it in — so both sections are tried, newest first.
  Future<String?> foregroundPackage() async {
    for (final section in const ['displays', 'windows']) {
      try {
        final result = await shell(['dumpsys', 'window', section]);
        if (result.exitCode != 0) continue;
        final package = parseForegroundPackage(processStdout(result));
        if (package != null) return package;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

final _foregroundPackagePatterns = [
  RegExp(r'mCurrentFocus=.*?\s([\w.]+)/[\w.$]+'),
  RegExp(r'mFocusedApp=.*?\s([\w.]+)/[\w.$]+'),
];

/// Extracts the focused package from `dumpsys window windows` output,
/// preferring the focused window over the focused activity so that system
/// dialogs (e.g. the permission controller) are reported.
String? parseForegroundPackage(String dumpsysOutput) {
  for (final pattern in _foregroundPackagePatterns) {
    final match = pattern.firstMatch(dumpsysOutput);
    if (match != null) return match.group(1);
  }
  return null;
}
