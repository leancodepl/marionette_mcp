import 'dart:io';

import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_native_device.dart';
import 'package:marionette_mcp/src/native_service/ios_native_device.dart';
import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/simctl_client.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';

const _app = 'com.example.counter';

/// `dumpsys package` excerpt as printed by API 28 / 35 emulators.
const _dumpsys = '''
Packages:
  Package [com.example.counter] (a1b2c3):
    requested permissions:
      android.permission.INTERNET
      android.permission.CAMERA
      android.permission.POST_NOTIFICATIONS: restricted=true
      android.permission.READ_MEDIA_IMAGES
      android.permission.READ_EXTERNAL_STORAGE
    install permissions:
      android.permission.INTERNET: granted=true
''';

void main() {
  group('permission mapping', () {
    test('Android names depend on the API level', () {
      expect(
        androidPermissionNames(NativePermission.photos, 28),
        ['android.permission.READ_EXTERNAL_STORAGE'],
      );
      expect(
        androidPermissionNames(NativePermission.photos, 34),
        [
          'android.permission.READ_MEDIA_IMAGES',
          'android.permission.READ_MEDIA_VIDEO',
          'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
        ],
      );
      expect(
          androidPermissionNames(NativePermission.notifications, 32), isEmpty);
      expect(
        androidPermissionNames(NativePermission.notifications, 33),
        ['android.permission.POST_NOTIFICATIONS'],
      );
      expect(
        androidPermissionNames(NativePermission.all, 33),
        containsAll([
          'android.permission.CAMERA',
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.POST_NOTIFICATIONS',
        ]),
      );
    });

    test('iOS services; notifications cannot be changed', () {
      expect(iosPrivacyService(NativePermission.camera), 'camera');
      expect(iosPrivacyService(NativePermission.all), 'all');
      expect(iosPrivacyService(NativePermission.notifications), isNull);
    });

    test('system apps (D7)', () {
      for (final id in [
        'com.android.launcher3',
        'com.google.android.permissioncontroller',
        'com.android.systemui',
        'com.apple.springboard',
        'com.apple.mobilesafari',
        'com.sec.android.app.launcher',
        'android',
      ]) {
        expect(isSystemAppId(id), isTrue, reason: id);
      }
      expect(isSystemAppId(_app), isFalse);
    });
  });

  group('AndroidNativeDevice', () {
    late FakeProcessRunner runner;
    late AndroidNativeDevice device;

    void sdk(int level) =>
        runner.onAdb(['shell', 'getprop', 'ro.build.version.sdk'],
            result: ok('$level\n'));

    setUp(() {
      runner = FakeProcessRunner()
        ..onAdb(['shell', 'dumpsys', 'package'], result: ok(_dumpsys));
      device = AndroidNativeDevice(
        AdbClient(serial: 'emulator-5554', processRunner: runner.call),
      );
    });

    test('parses requested permissions, including restricted ones', () {
      expect(parseRequestedPermissions(_dumpsys), {
        'android.permission.INTERNET',
        'android.permission.CAMERA',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_EXTERNAL_STORAGE',
      });
    });

    test('grant changes only permissions the app declares', () async {
      sdk(35);

      final change = await device.setPermission(
        NativePermissionAction.grant,
        NativePermission.photos,
        _app,
      );

      expect(change.nativeNames, ['android.permission.READ_MEDIA_IMAGES']);
      expect(
        runner.adbCommands.where((c) => c.length > 1 && c[1] == 'pm'),
        [
          [
            'shell',
            'pm',
            'grant',
            _app,
            'android.permission.READ_MEDIA_IMAGES'
          ],
        ],
      );
    });

    test('reset revokes and clears the user choice flags', () async {
      sdk(35);

      final change = await device.setPermission(
        NativePermissionAction.reset,
        NativePermission.camera,
        _app,
      );

      expect(change.notes, isEmpty);
      expect(
        runner.adbCommands.where((c) => c.length > 1 && c[1] == 'pm'),
        [
          ['shell', 'pm', 'revoke', _app, 'android.permission.CAMERA'],
          [
            'shell',
            'pm',
            'clear-permission-flags',
            _app,
            'android.permission.CAMERA',
            'user-set',
            'user-fixed',
          ],
        ],
      );
      expect(
        runner.adbCommands.expand((c) => c),
        isNot(contains('reset-permissions')),
        reason: 'pm reset-permissions resets every app on the device',
      );
    });

    test('reset on Android 9 revokes and explains the partial reset', () async {
      sdk(28);
      runner.onAdb(
        ['shell', 'pm', 'clear-permission-flags'],
        result: failed(stdout: 'Unknown command: clear-permission-flags'),
      );

      final change = await device.setPermission(
        NativePermissionAction.reset,
        NativePermission.camera,
        _app,
      );

      expect(change.nativeNames, ['android.permission.CAMERA']);
      expect(change.notes.single, contains("don't ask again"));
    });

    test('notifications before API 33 are unsupported', () async {
      sdk(32);

      await expectLater(
        device.setPermission(
          NativePermissionAction.grant,
          NativePermission.notifications,
          _app,
        ),
        throwsA(isA<NativeUnsupportedException>()),
      );
    });

    test('an undeclared permission or unknown app fails with a hint', () async {
      sdk(35);

      await expectLater(
        device.setPermission(
          NativePermissionAction.grant,
          NativePermission.location,
          _app,
        ),
        throwsA(
          isA<NativeOperationFailedException>()
              .having((e) => e.message, 'message', contains('manifest')),
        ),
      );
      await expectLater(
        device.setPermission(
          NativePermissionAction.grant,
          NativePermission.camera,
          'com.missing',
        ),
        throwsA(
          isA<NativeOperationFailedException>()
              .having((e) => e.message, 'message', contains('not installed')),
        ),
      );
    });

    test('a failing pm command becomes a typed error', () async {
      sdk(35);
      runner.onAdb(
        ['shell', 'pm', 'grant'],
        result: failed(
          exitCode: 255,
          stderr: 'Exception occurred while executing grant',
        ),
      );

      await expectLater(
        device.setPermission(
          NativePermissionAction.grant,
          NativePermission.camera,
          _app,
        ),
        throwsA(isA<NativeOperationFailedException>()),
      );
    });

    test('activateApp starts the resolved launcher activity (D11)', () async {
      runner.onAdb(
        ['shell', 'cmd', 'package', 'resolve-activity'],
        result: ok('priority=0 preferredOrder=0\n$_app/.MainActivity\n'),
      );

      await device.activateApp(_app);

      expect(runner.adbCommands.last,
          ['shell', 'am', 'start', '-n', '$_app/.MainActivity']);
    });

    test('activateApp falls back to monkey, then fails with a hint', () async {
      runner.onAdb(
        ['shell', 'cmd', 'package', 'resolve-activity'],
        result: ok('No activity found\n'),
      );

      await device.activateApp(_app);
      expect(runner.adbCommands.last.sublist(0, 4),
          ['shell', 'monkey', '-p', _app]);

      runner.onAdb(['shell', 'monkey'],
          result: ok('** No activities found to run, monkey aborted.'));
      await expectLater(
        device.activateApp('com.missing'),
        throwsA(isA<NativeOperationFailedException>()),
      );
    });

    test('terminateApp reports whether the app was running', () async {
      runner.onAdb(['shell', 'pidof'], result: ok('1234\n'));
      expect(await device.terminateApp(_app), isTrue);
      expect(runner.adbCommands.last, ['shell', 'am', 'force-stop', _app]);

      runner.onAdb(['shell', 'pidof'], result: failed());
      expect(await device.terminateApp(_app), isFalse);
    });

    test('openUrl quotes the URL for the device shell', () async {
      await device.openUrl("myapp://a/b?x=1&y='2'");

      expect(runner.adbCommands.last, [
        'shell',
        'am',
        'start',
        '-a',
        'android.intent.action.VIEW',
        '-d',
        r"'myapp://a/b?x=1&y='\''2'\'''",
      ]);
    });

    test('openUrl without a handler fails with a hint', () async {
      runner.onAdb(
        ['shell', 'am', 'start'],
        result: ok('Error: Activity not started, unable to resolve Intent'),
      );

      await expectLater(
        device.openUrl('nope://x'),
        throwsA(isA<NativeOperationFailedException>()),
      );
    });

    test('notifications use cmd statusbar; push is unsupported', () async {
      await device.openNotifications();
      await device.closeNotifications();

      expect(runner.adbCommands, [
        ['shell', 'cmd', 'statusbar', 'expand-notifications'],
        ['shell', 'cmd', 'statusbar', 'collapse'],
      ]);
      expect(
        () => device.pushNotification(_app, const {'aps': <String, dynamic>{}}),
        throwsA(isA<NativeUnsupportedException>()),
      );
    });

    test('location: longitude first, emulators only', () async {
      await device.setLocation(52.23, 21.01);
      expect(runner.adbCommands.last, ['emu', 'geo', 'fix', '21.01', '52.23']);

      final physical = AndroidNativeDevice(
        AdbClient(serial: 'R58M123', processRunner: runner.call),
      );
      await expectLater(
        physical.setLocation(1, 1),
        throwsA(isA<NativeUnsupportedException>()),
      );
    });

    test('info reads system properties', () async {
      sdk(28);
      runner
        ..onAdb(['shell', 'getprop', 'ro.build.version.release'],
            result: ok('9\n'))
        ..onAdb(['shell', 'getprop', 'ro.product.model'],
            result: ok('Pixel 3\n'))
        ..onAdb(['shell', 'getprop', 'ro.kernel.qemu'], result: ok('1\n'));

      final info = await device.info();

      expect(info.toJson(), {
        'osVersion': 'Android 9',
        'apiLevel': 28,
        'model': 'Pixel 3',
        'isEmulator': true,
        'id': 'emulator-5554',
      });
    });
  });

  group('IosNativeDevice', () {
    const udid = 'SIM-1';
    late FakeProcessRunner runner;
    late IosNativeDevice device;

    List<List<String>> simctl() => runner.calls
        .where((c) => c.executable == 'xcrun')
        .map((c) => c.arguments)
        .toList();

    setUp(() {
      runner = FakeProcessRunner();
      device = IosNativeDevice(SimctlClient(processRunner: runner.call), udid);
    });

    test('permissions go through simctl privacy', () async {
      final change = await device.setPermission(
        NativePermissionAction.reset,
        NativePermission.camera,
        _app,
      );

      expect(change.nativeNames, ['camera']);
      expect(simctl().single,
          ['simctl', 'privacy', udid, 'reset', 'camera', _app]);
    });

    test('notifications permission is unsupported, with a hint', () async {
      await expectLater(
        device.setPermission(
          NativePermissionAction.grant,
          NativePermission.notifications,
          _app,
        ),
        throwsA(
          isA<NativeUnsupportedException>()
              .having((e) => e.hint, 'hint', contains('native_tap')),
        ),
      );
      expect(simctl(), isEmpty);
    });

    test('photos: grant and revoke are unsupported, reset works', () async {
      await expectLater(
        device.setPermission(
          NativePermissionAction.grant,
          NativePermission.photos,
          _app,
        ),
        throwsA(
          isA<NativeUnsupportedException>()
              .having((e) => e.hint, 'hint', contains('Allow Full Access')),
        ),
      );
      await device.setPermission(
        NativePermissionAction.reset,
        NativePermission.photos,
        _app,
      );
      expect(simctl().single,
          ['simctl', 'privacy', udid, 'reset', 'photos', _app]);
    });

    test('all: grant goes service by service, reset uses simctl all', () async {
      final change = await device.setPermission(
        NativePermissionAction.grant,
        NativePermission.all,
        _app,
      );

      expect(change.nativeNames,
          ['camera', 'microphone', 'location', 'contacts', 'calendar']);
      expect(change.notes.single, contains('Skipped photos and notifications'));
      expect(simctl().map((c) => c[4]),
          ['camera', 'microphone', 'location', 'contacts', 'calendar']);

      runner.calls.clear();
      await device.setPermission(
        NativePermissionAction.reset,
        NativePermission.all,
        _app,
      );
      expect(
          simctl().single, ['simctl', 'privacy', udid, 'reset', 'all', _app]);
    });

    test('a failing simctl becomes a typed error', () async {
      runner.on('xcrun', ['simctl', 'privacy'],
          result: failed(stderr: 'Invalid device'));

      await expectLater(
        device.setPermission(
          NativePermissionAction.grant,
          NativePermission.camera,
          _app,
        ),
        throwsA(isA<NativeOperationFailedException>()),
      );
    });

    test('app lifecycle and URLs', () async {
      await device.activateApp(_app);
      await device.openUrl('https://example.com');
      expect(simctl(), [
        ['simctl', 'launch', udid, _app],
        ['simctl', 'openurl', udid, 'https://example.com'],
      ]);

      runner.on('xcrun', ['simctl', 'terminate'],
          result: failed(exitCode: 3, stderr: 'found nothing to terminate'));
      expect(await device.terminateApp(_app), isFalse);
    });

    test('isAppRunning reads launchctl inside the simulator', () async {
      runner.on('xcrun', ['simctl', 'spawn'],
          result: ok('PID\tStatus\tLabel\n'
              '55167\t0\tUIKitApplication:$_app[e8fc][rb-legacy]\n'
              '-\t0\tUIKitApplication:com.other[1]\n'));

      expect(await device.isAppRunning(_app), isTrue);
      expect(await device.isAppRunning('com.other'), isFalse);
    });

    test('push writes the payload to a file for simctl', () async {
      String? sent;
      runner.on('xcrun', ['simctl', 'push'], respond: (args) {
        sent = File(args.last).readAsStringSync();
        return ok();
      });

      await device.pushNotification(_app, const {
        'aps': {'alert': 'Hi'},
      });

      expect(sent, '{"aps":{"alert":"Hi"}}');
    });

    test('notification center needs a gesture', () {
      expect(
          device.openNotifications, throwsA(isA<NativeUnsupportedException>()));
    });

    test('info names the simulator and runtime', () async {
      runner.on('xcrun', ['simctl', 'list'], result: ok('''
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
  {"udid": "$udid", "name": "iPhone 16 Pro Max", "state": "Booted"}]}}
'''));

      expect((await device.info()).toJson(), {
        'osVersion': 'iOS 18.6',
        'model': 'iPhone 16 Pro Max',
        'isEmulator': true,
        'id': udid,
      });
    });
  });
}
