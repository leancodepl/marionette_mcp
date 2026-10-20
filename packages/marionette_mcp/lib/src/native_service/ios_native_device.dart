import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/process.dart';
import 'package:marionette_mcp/src/native_service/simctl_client.dart';

/// [NativeDevice] for an iOS Simulator, over `xcrun simctl`.
final class IosNativeDevice implements NativeDevice {
  IosNativeDevice(this._simctl, this.udid);

  final SimctlClient _simctl;

  /// The simulator this device controls.
  final String udid;

  @override
  Future<NativeDeviceInfo> info() async {
    final simulator =
        await _guard('simctl list', () => _simctl.deviceInfo(udid));
    return NativeDeviceInfo(
      osVersion: simulator?.runtime ?? 'iOS',
      model: simulator?.name ?? 'iOS Simulator',
      isEmulator: true,
      id: udid,
    );
  }

  @override
  Future<NativePermissionChange> setPermission(
    NativePermissionAction action,
    NativePermission permission,
    String appId,
  ) async {
    // `simctl privacy … all` resets every service, but grants or revokes
    // only some of them (iOS 26.4: location only), so grant / revoke of
    // `all` changes the services one by one
    // (docs/native-lane-decisions.md#d17).
    if (permission == NativePermission.all &&
        action != NativePermissionAction.reset) {
      final services = [
        for (final single in NativePermission.values)
          if (single != NativePermission.all &&
              _canChange(action, single) == null)
            iosPrivacyService(single)!,
      ];
      for (final service in services) {
        await _privacy(action, service, appId);
      }
      return NativePermissionChange(
        nativeNames: services,
        notes: [
          'Skipped photos and notifications: the simulator cannot '
              '${action.name} them. ${_dialogHint('the app asks')}',
        ],
      );
    }

    final unsupported = _canChange(action, permission);
    if (unsupported != null) {
      throw NativeUnsupportedException(unsupported, hint: _dialogHint(''));
    }
    final service = iosPrivacyService(permission)!;
    await _privacy(action, service, appId);
    return NativePermissionChange(nativeNames: [service]);
  }

  /// Why [action] cannot be applied to [permission] on the simulator, or
  /// null when it can.
  static String? _canChange(
    NativePermissionAction action,
    NativePermission permission,
  ) {
    if (permission == NativePermission.notifications) {
      return 'The iOS Simulator cannot change the notifications permission '
          '(simctl privacy has no such service).';
    }
    // simctl records photos as allowed, but the full-access Photo Library
    // API (iOS 14+) ignores it and still asks; reset works.
    if (permission == NativePermission.photos &&
        action != NativePermissionAction.reset) {
      return 'The iOS Simulator cannot ${action.name} full Photo Library '
          'access: simctl privacy photos is ignored by iOS 14+ (the app '
          'still asks). reset works.';
    }
    return null;
  }

  static String _dialogHint(String when) =>
      '${when.isEmpty ? 'Let the app ask' : 'When $when'}, answer the system '
      'alert with native_tap (e.g. text "Allow" or "Allow Full Access"); '
      'native_wait_for helps to wait for it.';

  Future<void> _privacy(
    NativePermissionAction action,
    String service,
    String appId,
  ) =>
      _guard(
        'simctl privacy',
        () => _simctl.privacy(udid, action.name, service, appId),
      );

  @override
  Future<void> openUrl(String url) =>
      _guard('simctl openurl', () => _simctl.openUrl(udid, url));

  /// `simctl launch` starts the app, or brings the running instance to the
  /// front with its state (same process) when it is already running
  /// (docs/native-lane-decisions.md#d11).
  @override
  Future<void> activateApp(String appId) =>
      _guard('simctl launch', () => _simctl.launch(udid, appId));

  @override
  Future<bool> terminateApp(String appId) async {
    try {
      await _simctl.terminate(udid, appId);
      return true;
    } on ProcessCommandException catch (error) {
      if (error.output.contains('found nothing to terminate')) return false;
      throw _failed('simctl terminate', error);
    }
  }

  @override
  Future<bool?> isAppRunning(String appId) => _simctl.isAppRunning(udid, appId);

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

  @override
  Future<void> pushNotification(
    String appId,
    Map<String, dynamic> payload,
  ) async {
    final directory = await Directory.systemTemp.createTemp('marionette_push');
    try {
      final file = File('${directory.path}/payload.apns')
        ..writeAsStringSync(jsonEncode(payload));
      await _guard(
        'simctl push',
        () => _simctl.push(udid, appId, file.path),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> setLocation(double latitude, double longitude) => _guard(
        'simctl location',
        () => _simctl.setLocation(udid, latitude, longitude),
      );

  /// The Simulator's Features → Face ID / Touch ID menu posts these
  /// notifications; `notifyutil` posts the same ones. Matches are sent for
  /// both Face ID (`pearl`) and Touch ID (`fingerTouch`): a simulator only
  /// listens to its own.
  @override
  Future<void> biometrics(NativeBiometricAction action) => _guard(
        'notifyutil',
        () async {
          const enrollment = 'com.apple.BiometricKit.enrollmentChanged';
          switch (action) {
            case NativeBiometricAction.enroll:
              await _simctl.notify(udid, enrollment, state: 1);
            case NativeBiometricAction.unenroll:
              await _simctl.notify(udid, enrollment, state: 0);
            case NativeBiometricAction.match:
            case NativeBiometricAction.nonMatch:
              final suffix =
                  action == NativeBiometricAction.match ? 'match' : 'nomatch';
              for (final sensor in const ['pearl', 'fingerTouch']) {
                await _simctl.notify(
                  udid,
                  'com.apple.BiometricKit_Sim.$sensor.$suffix',
                );
              }
          }
        },
      );

  Future<T> _guard<T>(String what, Future<T> Function() operation) async {
    try {
      return await operation();
    } on ProcessCommandException catch (error) {
      throw _failed(what, error);
    } on ProcessException catch (error) {
      throw NativeOperationFailedException(
        'Could not run $what: ${error.message}',
        hint: 'Check that Xcode command line tools (xcrun) are installed.',
      );
    }
  }

  static NativeOperationFailedException _failed(
    String what,
    ProcessCommandException error,
  ) =>
      NativeOperationFailedException(
        '$what failed: ${error.output}',
        hint: 'Check that the simulator is booted and that appId is the '
            'bundle id of an installed app.',
      );
}
