import 'dart:io';

import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/poll.dart';
import 'package:marionette_mcp/src/native_service/process.dart';

/// [NativeDevice] for an Android device or emulator, over `adb`.
final class AndroidNativeDevice implements NativeDevice {
  AndroidNativeDevice(this._adb);

  final AdbClient _adb;

  @override
  Future<void> openNotifications() async {
    _check(
      await _adb.shell(['cmd', 'statusbar', 'expand-notifications']),
      'cmd statusbar',
    );
    await _waitForShade(open: true);
  }

  @override
  Future<void> closeNotifications() async {
    _check(
      await _adb.shell(['cmd', 'statusbar', 'collapse']),
      'cmd statusbar',
    );
    await _waitForShade(open: false);
  }

  /// `cmd statusbar` returns while the shade is still moving; a read right
  /// after it reported the app as foregroundApp next to the shade's
  /// notifications. Waits (at most 1.8 s) until the shade has or has lost
  /// focus.
  Future<void> _waitForShade({required bool open}) async {
    final settled = await pollUntil(
      () async =>
          (await _adb.foregroundPackage() == 'com.android.systemui') == open,
      attempts: _shadeChecks,
      interval: _shadeCheckInterval,
    );
    if (settled) return;
    throw NativeOperationFailedException(
      'The Android notification shade did not ${open ? 'open' : 'close'}.',
      hint: 'Wait until the system UI settles, then retry.',
    );
  }

  /// Turns a failed command into a [NativeOperationFailedException].
  void _check(ProcessResult result, String what) {
    final stderr = '${result.stderr}'.trim();
    if (result.exitCode == 0 && !stderr.startsWith('Exception')) return;
    throw NativeOperationFailedException(
      '$what failed: ${processMessage(result)}',
      hint: 'Check that adb can reach the device.',
    );
  }
}

/// How often and how long the shade is checked after `cmd statusbar`
/// (the last check at 1.8 s).
const _shadeChecks = 10;
const _shadeCheckInterval = Duration(milliseconds: 200);
