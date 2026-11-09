import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_native_device.dart';
import 'package:marionette_mcp/src/native_service/ios_native_device.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';

const _app = 'com.example.counter';

void main() {
  group('AndroidNativeDevice', () {
    late FakeProcessRunner runner;
    late AndroidNativeDevice device;

    setUp(() {
      runner = FakeProcessRunner();
      device = AndroidNativeDevice(
        AdbClient(serial: 'emulator-5554', processRunner: runner.call),
      );
    });

    test('notifications use cmd statusbar and wait for the shade', () async {
      // The shade takes focus a moment after the command (seen on API 35):
      // the first read still shows the app.
      var shade = false;
      var readsUntilMoved = 0;
      runner
        ..onAdb(['shell', 'cmd', 'statusbar'], respond: (args) {
          shade = args.last == 'expand-notifications';
          readsUntilMoved = 1;
          return ok();
        })
        ..onAdb(['shell', 'dumpsys', 'window'], respond: (_) {
          final moved = readsUntilMoved-- <= 0;
          final focus = moved == shade
              ? 'Window{6bb05b2 u0 NotificationShade}'
              : 'Window{a719f4f u0 $_app/$_app.MainActivity}';
          return ok('  mCurrentFocus=$focus\n');
        });

      await device.openNotifications();
      final afterOpen = runner.adbCommands.length;
      await device.closeNotifications();

      List<String> command(List<String> c) => c.take(4).toList();
      expect(runner.adbCommands.take(afterOpen).map(command), [
        ['shell', 'cmd', 'statusbar', 'expand-notifications'],
        ['shell', 'dumpsys', 'window', 'displays'],
        ['shell', 'dumpsys', 'window', 'displays'],
      ]);
      expect(runner.adbCommands.skip(afterOpen).map(command), [
        ['shell', 'cmd', 'statusbar', 'collapse'],
        ['shell', 'dumpsys', 'window', 'displays'],
        ['shell', 'dumpsys', 'window', 'displays'],
      ]);
    });

    test('a failing statusbar command becomes a typed error', () async {
      runner.onAdb(['shell', 'cmd', 'statusbar'],
          result: failed(stderr: 'no statusbar'));

      await expectLater(
        device.openNotifications(),
        throwsA(isA<NativeOperationFailedException>()),
      );
    });
  });

  group('IosNativeDevice', () {
    test('notification center needs a gesture', () {
      const device = IosNativeDevice();
      expect(
          device.openNotifications, throwsA(isA<NativeUnsupportedException>()));
      expect(device.closeNotifications,
          throwsA(isA<NativeUnsupportedException>()));
    });
  });
}
