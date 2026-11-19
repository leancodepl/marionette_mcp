import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_native_device.dart';
import 'package:marionette_mcp/src/native_service/ios_native_device.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:test/test.dart';

import 'support/fake_native_connector.dart';
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

    test('a shade that never reaches the requested state becomes an error',
        () async {
      runner
        ..onAdb(['shell', 'cmd', 'statusbar'], respond: (_) => ok())
        ..onAdb(
          ['shell', 'dumpsys', 'window'],
          respond: (_) => ok('mCurrentFocus=Window{1 u0 $_app/.MainActivity}'),
        );

      await expectLater(
        device.openNotifications(),
        throwsA(
          isA<NativeOperationFailedException>().having(
            (error) => error.hint,
            'hint',
            contains('retry'),
          ),
        ),
      );
    });
  });

  group('IosNativeDevice', () {
    test('notification center uses edge gestures', () async {
      final connector = FakeNativeConnector(
        screen: const NativeScreen(width: 1000, height: 2000, scale: 1),
      );
      final device = IosNativeDevice(connector);

      await device.openNotifications();
      await device.closeNotifications();

      expect(connector.swipes, [
        (startX: 333, startY: 1, endX: 333, endY: 1200),
        (startX: 500, startY: 1999, endX: 500, endY: 1000),
      ]);
    });

    test('retries a swipe that did not open it from the home screen', () async {
      // Seen on iOS 26.4: with a banner on screen, the first swipe missed.
      final connector = FakeNativeConnector(
        foregroundAppValue: 'com.apple.springboard',
      );
      connector.onGetElements = (_) => [
            if (connector.swipes.length > 1)
              nativeElement(
                type: 'XCUIElementTypeWindow',
                id: 'SBCoverSheetWindow',
              ),
          ];

      await IosNativeDevice(connector).openNotifications();

      expect(connector.swipes, hasLength(2));
    });

    test('reports a Notification Center that did not open', () async {
      final connector = FakeNativeConnector(
        foregroundAppValue: 'com.apple.springboard',
      );

      await expectLater(
        IosNativeDevice(connector).openNotifications(),
        throwsA(
          isA<NativeOperationFailedException>().having(
            (error) => error.message,
            'message',
            contains('did not open'),
          ),
        ),
      );
    });
  });
}
