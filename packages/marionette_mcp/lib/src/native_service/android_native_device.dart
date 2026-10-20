import 'dart:io';

import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/process.dart';

/// [NativeDevice] for an Android device or emulator, over `adb`.
final class AndroidNativeDevice implements NativeDevice {
  AndroidNativeDevice(this._adb);

  final AdbClient _adb;
  int? _sdk;

  @override
  Future<NativeDeviceInfo> info() async {
    final release = await _prop('ro.build.version.release');
    final model = await _prop('ro.product.model');
    final qemu = await _prop('ro.kernel.qemu');
    final serial = await _adb.resolveSerial();
    return NativeDeviceInfo(
      osVersion: 'Android $release',
      apiLevel: await _sdkLevel(),
      model: model,
      isEmulator: qemu == '1' || (serial?.startsWith('emulator-') ?? false),
      id: serial,
    );
  }

  /// See docs/native-lane-decisions.md#d17. grant / revoke use
  /// `pm grant|revoke`; reset revokes and clears the
  /// "user set" / "don't ask again" flags (`pm clear-permission-flags`, API
  /// 30+), so the app asks again. `pm reset-permissions` is not used: it
  /// ignores the package and resets every app on the device.
  @override
  Future<NativePermissionChange> setPermission(
    NativePermissionAction action,
    NativePermission permission,
    String appId,
  ) async {
    final sdk = await _sdkLevel();
    final candidates = androidPermissionNames(permission, sdk);
    if (candidates.isEmpty) {
      throw NativeUnsupportedException(
        'Android $sdk has no runtime permission for ${permission.name}.',
        hint: permission == NativePermission.notifications
            ? 'Before Android 13 (API 33) apps may post notifications '
                'without asking; nothing to change.'
            : null,
      );
    }

    final requested = await _requestedPermissions(appId);
    final names = candidates.where(requested.contains).toList();
    if (names.isEmpty) {
      throw NativeOperationFailedException(
        '$appId does not declare ${candidates.join(' / ')} in its manifest, '
        'so ${permission.name} cannot be changed.',
        hint: 'Check appId, or add the permission to AndroidManifest.xml.',
      );
    }

    final notes = <String>[];
    var flagsCleared = true;
    for (final name in names) {
      switch (action) {
        case NativePermissionAction.grant:
          await _pm(['grant', appId, name]);
        case NativePermissionAction.revoke:
          await _pm(['revoke', appId, name]);
        case NativePermissionAction.reset:
          await _pm(['revoke', appId, name]);
          if (flagsCleared) {
            flagsCleared = await _clearUserFlags(appId, name);
          }
      }
    }
    if (!flagsCleared) {
      notes.add('Android $sdk cannot clear the "don\'t ask again" choice '
          '(pm clear-permission-flags needs Android 11, API 30): the '
          'permission is '
          'revoked, but if the user had picked "don\'t ask again" the app '
          'will not ask. Reinstall the app for a full reset.');
    }
    return NativePermissionChange(nativeNames: names, notes: notes);
  }

  /// Clears the flags that record the user's choice; false when this
  /// Android version has no such command.
  Future<bool> _clearUserFlags(String appId, String permission) async {
    final result = await _adb.shell(
      [
        'pm',
        'clear-permission-flags',
        appId,
        permission,
        'user-set',
        'user-fixed'
      ],
    );
    final output = '${processStdout(result)}${result.stderr}';
    if (output.contains('Unknown command')) return false;
    _check(result, 'pm clear-permission-flags');
    return true;
  }

  Future<Set<String>> _requestedPermissions(String appId) async {
    final result = await _adb.shell(['dumpsys', 'package', appId]);
    _check(result, 'dumpsys package');
    final output = processStdout(result);
    if (!output.contains('Package [$appId]')) {
      throw NativeOperationFailedException(
        'App $appId is not installed on the device.',
        hint: 'Pass the package name of the app under test as appId.',
      );
    }
    return parseRequestedPermissions(output);
  }

  @override
  Future<void> openUrl(String url) async {
    final result = await _adb.shell([
      'am',
      'start',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      shellQuote(url),
    ]);
    _check(result, 'am start');
    final output = processStdout(result);
    if (output.contains('Error:')) {
      throw NativeOperationFailedException(
        'No app can open $url: ${output.trim()}',
        hint: 'Check the URL scheme, or that the app declares an intent '
            'filter for it.',
      );
    }
  }

  /// `cmd package resolve-activity` + `am start -n`
  /// (docs/native-lane-decisions.md#d11), which brings an
  /// existing task to the front instead of creating a new instance; `monkey`
  /// as a fallback for unusual manifests.
  @override
  Future<void> activateApp(String appId) async {
    final resolved = await _adb.shell(
      ['cmd', 'package', 'resolve-activity', '--brief', appId],
    );
    final activity = processStdout(resolved)
        .split('\n')
        .map((line) => line.trim())
        .lastWhere((line) => line.startsWith('$appId/'), orElse: () => '');
    if (resolved.exitCode == 0 && activity.isNotEmpty) {
      final started = await _adb.shell(['am', 'start', '-n', activity]);
      if (started.exitCode == 0 && !processStdout(started).contains('Error:')) {
        return;
      }
    }

    final monkey = await _adb.shell([
      'monkey',
      '-p',
      appId,
      '-c',
      'android.intent.category.LAUNCHER',
      '1',
    ]);
    if (monkey.exitCode != 0 ||
        processStdout(monkey).contains('No activities found')) {
      throw NativeOperationFailedException(
        'Could not start $appId: no launchable activity '
        '(is the app installed?).',
        hint: 'Pass the package name of an installed app as appId.',
      );
    }
  }

  @override
  Future<bool> terminateApp(String appId) async {
    final wasRunning = await isAppRunning(appId);
    _check(await _adb.shell(['am', 'force-stop', appId]), 'am force-stop');
    return wasRunning ?? true;
  }

  @override
  Future<bool?> isAppRunning(String appId) async {
    try {
      final result = await _adb.shell(['pidof', appId]);
      return processStdout(result).trim().isNotEmpty;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openNotifications() async => _check(
        await _adb.shell(['cmd', 'statusbar', 'expand-notifications']),
        'cmd statusbar',
      );

  @override
  Future<void> closeNotifications() async => _check(
        await _adb.shell(['cmd', 'statusbar', 'collapse']),
        'cmd statusbar',
      );

  @override
  Future<void> pushNotification(
    String appId,
    Map<String, dynamic> payload,
  ) =>
      throw const NativeUnsupportedException(
        'Android cannot receive a simulated push notification from outside '
        'the app.',
        hint: 'Send a real one (e.g. Firebase Cloud Messaging), or let the '
            'app post a local notification.',
      );

  /// `adb emu geo fix` — emulators only. Note the longitude-first order.
  @override
  Future<void> setLocation(double latitude, double longitude) async {
    final serial = await _adb.resolveSerial();
    if (serial == null || !serial.startsWith('emulator-')) {
      throw const NativeUnsupportedException(
        'A location can only be simulated on an Android emulator.',
        hint: 'On a physical device use a mock-location app.',
      );
    }
    final result =
        await _adb.run(['emu', 'geo', 'fix', '$longitude', '$latitude']);
    _check(result, 'adb emu geo fix');
  }

  /// `adb emu finger touch` on an emulator: finger 1 is the one enrolled
  /// through Settings, finger 2 is never enrolled. Enrolling cannot be done
  /// with a command.
  @override
  Future<void> biometrics(NativeBiometricAction action) async {
    final serial = await _adb.resolveSerial();
    if (serial == null || !serial.startsWith('emulator-')) {
      throw const NativeUnsupportedException(
        'Biometrics can only be simulated on an Android emulator.',
        hint: 'On a physical device use a real finger.',
      );
    }
    switch (action) {
      case NativeBiometricAction.enroll:
      case NativeBiometricAction.unenroll:
        throw NativeUnsupportedException(
          'Android has no command to ${action.name} a fingerprint.',
          hint: action == NativeBiometricAction.enroll
              ? 'Set a screen lock (adb shell locksettings set-pin 1111), '
                  'open Settings → Security → Fingerprint (or start '
                  'android.settings.FINGERPRINT_ENROLL), and answer every '
                  '"touch the sensor" step with native_biometrics '
                  'action=match.'
              : 'Remove it in Settings → Security → Fingerprint.',
        );
      case NativeBiometricAction.match:
      case NativeBiometricAction.nonMatch:
        final finger = action == NativeBiometricAction.match ? '1' : '2';
        _check(
          await _adb.run(['emu', 'finger', 'touch', finger]),
          'adb emu finger touch',
        );
    }
  }

  Future<int> _sdkLevel() async =>
      _sdk ??= int.tryParse(await _prop('ro.build.version.sdk')) ?? 0;

  Future<String> _prop(String name) async {
    final result = await _adb.shell(['getprop', name]);
    _check(result, 'getprop');
    return processStdout(result).trim();
  }

  Future<void> _pm(List<String> arguments) async =>
      _check(await _adb.shell(['pm', ...arguments]), 'pm ${arguments.first}');

  /// Turns a failed command into a [NativeOperationFailedException].
  void _check(ProcessResult result, String what) {
    final stderr = '${result.stderr}'.trim();
    if (result.exitCode == 0 && !stderr.startsWith('Exception')) return;
    throw NativeOperationFailedException(
      '$what failed: ${processMessage(result)}',
      hint: 'Check that adb can reach the device and that appId is right.',
    );
  }
}

/// Permissions listed under `requested permissions:` in
/// `adb shell dumpsys package <pkg>` output.
Set<String> parseRequestedPermissions(String dumpsys) {
  final permissions = <String>{};
  var inSection = false;
  for (final raw in dumpsys.split('\n')) {
    final line = raw.trim();
    if (line == 'requested permissions:') {
      inSection = true;
      continue;
    }
    if (!inSection) continue;
    if (line.isEmpty || line.endsWith(':')) break;
    // API 30+ may append flags: `android.permission.X: restricted=true`.
    permissions.add(line.split(':').first.trim());
  }
  return permissions;
}

/// Quotes [value] for the device shell that `adb shell` runs commands in,
/// so characters like `&` and `?` in a URL reach `am` unchanged.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";
