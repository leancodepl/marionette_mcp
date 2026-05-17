import 'dart:io';

/// Signature for running a process — injectable for testing.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Result of an [PermissionAccepter.accept] call.
class PermissionAcceptResult {
  PermissionAcceptResult({
    required this.success,
    required this.message,
    this.platform,
    this.buttonLabel,
  });

  /// `true` when a permission button was located and tapped.
  final bool success;

  /// Human-readable summary, suitable for surfacing back to the MCP client.
  final String message;

  /// `'android'` or `'ios'` when a target was selected, `null` otherwise.
  final String? platform;

  /// The label of the button that was tapped on success.
  final String? buttonLabel;
}

/// Common labels for "accept" buttons on system permission dialogs.
///
/// Ordered by preference: more specific labels first, so that "Allow only
/// while using the app" wins over a bare "Allow" if both appear (Android
/// runtime permission dialogs in API 30+ show both kinds at once).
const _acceptLabels = <String>[
  // Android — most-specific first
  'Allow only while using the app',
  'While using the app',
  'Only this time',
  'Allow all the time',
  'Allow',
  // iOS
  'Allow While Using App',
  'Allow Once',
  // Generic fallbacks for non-permission confirmation dialogs that still
  // block the app (rare, but harmless to try last).
  'OK',
  'Continue',
];

/// Locates and taps an "accept" button on a native OS permission dialog
/// that is overlaying the Flutter app.
///
/// The dialog is rendered by the OS (Android's `PackageInstaller` /
/// `permissioncontroller`, or iOS's SpringBoard) and lives outside the
/// Flutter widget tree, so the regular `tap` tool cannot reach it. This
/// helper shells out to platform tooling instead:
///
///   * Android — `adb shell uiautomator dump` to read the visible UI,
///     then `adb shell input tap` on the matched button's center.
///   * iOS Simulator — AppleScript via `osascript` to drive the Simulator
///     app's UI (`System Events > Simulator > click button "..."`).
///
/// Auto-detects the target: requires exactly one connected Android device
/// **or** one booted iOS simulator. Reports an actionable error otherwise.
class PermissionAccepter {
  PermissionAccepter({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  Future<PermissionAcceptResult> accept() async {
    final androidDevices = await _listAndroidDevices();
    final iosSimulators = await _listIosBootedSimulators();

    final total = androidDevices.length + iosSimulators.length;
    if (total == 0) {
      return PermissionAcceptResult(
        success: false,
        message: 'No connected Android devices or booted iOS simulators were '
            'detected. Plug in a device (or boot a simulator) and ensure '
            '`adb`/`xcrun` are on PATH.',
      );
    }
    if (total > 1) {
      final parts = <String>[
        if (androidDevices.isNotEmpty) 'Android: ${androidDevices.join(', ')}',
        if (iosSimulators.isNotEmpty) 'iOS: ${iosSimulators.join(', ')}',
      ];
      return PermissionAcceptResult(
        success: false,
        message: 'Multiple targets detected (${parts.join('; ')}). '
            'accept_permission requires exactly one connected device.',
      );
    }

    if (androidDevices.length == 1) {
      return _acceptOnAndroid(androidDevices.single);
    }
    return _acceptOnIosSimulator(iosSimulators.single);
  }

  Future<List<String>> _listAndroidDevices() async {
    try {
      final result = await _run('adb', ['devices']);
      if (result.exitCode != 0) return const [];
      final out = result.stdout as String;
      final devices = <String>[];
      for (final line in out.split('\n').skip(1)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1] == 'device') {
          devices.add(parts[0]);
        }
      }
      return devices;
    } on ProcessException {
      return const [];
    }
  }

  Future<List<String>> _listIosBootedSimulators() async {
    try {
      final result = await _run('xcrun', [
        'simctl',
        'list',
        'devices',
        'booted',
      ]);
      if (result.exitCode != 0) return const [];
      final out = result.stdout as String;
      // Lines look like: "    iPhone 15 Pro (UUID) (Booted)"
      final uuidPattern = RegExp(
        r'\(([0-9A-Fa-f-]{36})\)\s+\(Booted\)',
      );
      final udids = <String>[];
      for (final line in out.split('\n')) {
        final match = uuidPattern.firstMatch(line);
        if (match != null) udids.add(match.group(1)!);
      }
      return udids;
    } on ProcessException {
      return const [];
    }
  }

  Future<PermissionAcceptResult> _acceptOnAndroid(String serial) async {
    const dumpPath = '/sdcard/marionette_permission_dump.xml';

    final dump = await _run('adb', [
      '-s',
      serial,
      'shell',
      'uiautomator',
      'dump',
      dumpPath,
    ]);
    if (dump.exitCode != 0) {
      return PermissionAcceptResult(
        success: false,
        platform: 'android',
        message: 'Failed to dump UI hierarchy on $serial: '
            '${(dump.stderr as String).trim()}',
      );
    }

    final cat = await _run('adb', [
      '-s',
      serial,
      'shell',
      'cat',
      dumpPath,
    ]);
    if (cat.exitCode != 0) {
      return PermissionAcceptResult(
        success: false,
        platform: 'android',
        message: 'Failed to read UI dump on $serial: '
            '${(cat.stderr as String).trim()}',
      );
    }

    final match = findAcceptButton(cat.stdout as String);
    if (match == null) {
      return PermissionAcceptResult(
        success: false,
        platform: 'android',
        message: 'No accept-permission button found in the current UI on '
            '$serial. Searched for: ${_acceptLabels.join(', ')}.',
      );
    }

    final tap = await _run('adb', [
      '-s',
      serial,
      'shell',
      'input',
      'tap',
      '${match.x}',
      '${match.y}',
    ]);
    if (tap.exitCode != 0) {
      return PermissionAcceptResult(
        success: false,
        platform: 'android',
        buttonLabel: match.label,
        message: 'Failed to tap "${match.label}" at (${match.x},${match.y}) '
            'on $serial: ${(tap.stderr as String).trim()}',
      );
    }

    return PermissionAcceptResult(
      success: true,
      platform: 'android',
      buttonLabel: match.label,
      message: 'Tapped "${match.label}" at (${match.x},${match.y}) on '
          'Android device $serial.',
    );
  }

  Future<PermissionAcceptResult> _acceptOnIosSimulator(String udid) async {
    // The active dialog is owned by SpringBoard inside the Simulator app
    // window, so we drive it via Accessibility (System Events) rather than
    // `xcrun simctl privacy grant` — the latter persists permission state
    // but does not dismiss an already-presented dialog.
    for (final label in _acceptLabels) {
      final escaped = label.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      final result = await _run('osascript', [
        '-e',
        'tell application "System Events" to tell process "Simulator" to '
            'click button "$escaped" of window 1',
      ]);
      if (result.exitCode == 0) {
        return PermissionAcceptResult(
          success: true,
          platform: 'ios',
          buttonLabel: label,
          message: 'Clicked "$label" on iOS Simulator $udid.',
        );
      }
    }
    return PermissionAcceptResult(
      success: false,
      platform: 'ios',
      message: 'No accept-permission button found in the Simulator\'s '
          'frontmost window on $udid. Searched for: '
          '${_acceptLabels.join(', ')}. If the dialog is visible, grant the '
          'controlling terminal Accessibility access under System Settings > '
          'Privacy & Security > Accessibility.',
    );
  }
}

/// A node in the uiautomator dump that matches one of the accept labels.
class DumpMatch {
  DumpMatch(this.label, this.x, this.y);
  final String label;
  final int x;
  final int y;
}

/// Parses a uiautomator dump and returns the center of the first node whose
/// `text` matches an accept label, prioritizing more specific labels.
///
/// Visible for testing.
DumpMatch? findAcceptButton(String xml) {
  final nodeRegex = RegExp(r'<node\s+([^>]+?)\s*/?>');
  final attrRegex = RegExp(r'([\w-]+)="([^"]*)"');
  final boundsRegex = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]');

  final parsed = <Map<String, String>>[];
  for (final m in nodeRegex.allMatches(xml)) {
    final attrs = <String, String>{};
    for (final a in attrRegex.allMatches(m.group(1)!)) {
      attrs[a.group(1)!] = a.group(2)!;
    }
    parsed.add(attrs);
  }

  for (final label in _acceptLabels) {
    for (final attrs in parsed) {
      final text = attrs['text'] ?? '';
      if (text.toLowerCase() != label.toLowerCase()) continue;
      final b = boundsRegex.firstMatch(attrs['bounds'] ?? '');
      if (b == null) continue;
      final x1 = int.parse(b.group(1)!);
      final y1 = int.parse(b.group(2)!);
      final x2 = int.parse(b.group(3)!);
      final y2 = int.parse(b.group(4)!);
      return DumpMatch(label, (x1 + x2) ~/ 2, (y1 + y2) ~/ 2);
    }
  }
  return null;
}
