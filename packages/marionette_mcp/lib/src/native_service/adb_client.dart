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

  /// Serial of the device this client talks to: [serial] when set, otherwise
  /// the default device as reported by `adb get-serialno`. Null when it
  /// cannot be determined.
  Future<String?> resolveSerial() async {
    if (serial != null) return serial;
    try {
      final result = await run(const ['get-serialno']);
      final value = processStdout(result).trim();
      return result.exitCode == 0 && value.isNotEmpty ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// Local port of an existing `adb forward` from [deviceSerial] to device
  /// TCP port [remotePort], or null when there is none.
  Future<int?> forwardedLocalPort(String deviceSerial, int remotePort) async {
    try {
      final result = await _run('adb', const ['forward', '--list']);
      if (result.exitCode != 0) return null;
      return parseForwardedLocalPort(
        processStdout(result),
        deviceSerial: deviceSerial,
        remotePort: remotePort,
      );
    } catch (_) {
      return null;
    }
  }

  /// SHA-256 (lowercase hex) of the APK installed for [packageName], or null
  /// when the package is missing or the device cannot compute it (e.g. no
  /// `sha256sum` on old Android versions). Never throws.
  Future<String?> installedApkSha256(String packageName) async {
    try {
      final pathResult = await shell(['pm', 'path', packageName]);
      if (pathResult.exitCode != 0) return null;
      final apkPath = processStdout(pathResult)
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.startsWith('package:'), orElse: () => '')
          .replaceFirst('package:', '');
      if (apkPath.isEmpty) return null;

      final hashResult = await shell(['sha256sum', apkPath]);
      if (hashResult.exitCode != 0) return null;
      final hash = processStdout(hashResult).trim().split(RegExp(r'\s+')).first;
      return _sha256Pattern.hasMatch(hash) ? hash.toLowerCase() : null;
    } catch (_) {
      return null;
    }
  }

  /// Display size in pixels from `adb shell wm size` (an override size wins
  /// over the physical one), or null when it cannot be read. Never throws.
  Future<({int width, int height})?> screenSize() async {
    try {
      final result = await shell(const ['wm', 'size']);
      if (result.exitCode != 0) return null;
      return parseWmSize(processStdout(result));
    } catch (_) {
      return null;
    }
  }

  /// Whether the software keyboard (IME) is shown, from
  /// `dumpsys input_method`, or null when it cannot be read. Never throws.
  Future<bool?> isKeyboardShown() async {
    try {
      final result = await shell(const ['dumpsys', 'input_method']);
      if (result.exitCode != 0) return null;
      final match =
          RegExp(r'mInputShown=(true|false)').firstMatch(processStdout(result));
      return match == null ? null : match.group(1) == 'true';
    } catch (_) {
      return null;
    }
  }

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

final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

final _wmSizePattern = RegExp(r'(Physical|Override) size:\s*(\d+)x(\d+)');

/// Parses `adb shell wm size` output; an `Override size` (set with
/// `wm size WxH`) takes precedence over the `Physical size`.
({int width, int height})? parseWmSize(String output) {
  ({int width, int height})? physical;
  for (final match in _wmSizePattern.allMatches(output)) {
    final size = (
      width: int.parse(match.group(2)!),
      height: int.parse(match.group(3)!),
    );
    if (match.group(1) == 'Override') return size;
    physical = size;
  }
  return physical;
}

/// Parses `adb forward --list` output (`<serial> tcp:<local> tcp:<remote>`
/// per line) and returns the local port forwarded from [deviceSerial] to
/// [remotePort], if any.
int? parseForwardedLocalPort(
  String forwardList, {
  required String deviceSerial,
  required int remotePort,
}) {
  for (final line in forwardList.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 3 || parts[0] != deviceSerial) continue;
    if (parts[2] != 'tcp:$remotePort' || !parts[1].startsWith('tcp:')) {
      continue;
    }
    final port = int.tryParse(parts[1].substring(4));
    if (port != null) return port;
  }
  return null;
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
