import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/device_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import '../support/fake_native_connector.dart';

const _app = 'com.example.counter';

String _text(CallToolResult result) =>
    result.content.whereType<TextContent>().map((c) => c.text).join('\n');

Matcher _isToolError(Object textMatcher) => isA<CallToolResult>()
    .having((r) => r.isError, 'isError', isTrue)
    .having(_text, 'text', textMatcher);

Matcher _isToolSuccess(Object textMatcher) => isA<CallToolResult>()
    .having((r) => r.isError, 'isError', isFalse)
    .having(_text, 'text', textMatcher);

void main() {
  late FakeNativeConnector connector;
  late FakeNativeDevice device;
  late NativeServiceContext context;

  setUp(() async {
    connector = FakeNativeConnector(foregroundAppValue: _app);
    device = connector.device;
    context = NativeServiceContext(
      connectorFactory: (platform, {serial, udid}) async => connector,
    );
    await context.connect(NativePlatform.android);
  });

  group('default app (D7)', () {
    test('is the first non-system foreground app of the session', () async {
      expect(context.defaultAppId, _app);

      context.observeForegroundApp('com.other.app');
      expect(context.defaultAppId, _app, reason: 'the first one wins');
    });

    test('system apps are skipped; unknown app asks for appId', () async {
      connector.foregroundAppValue = 'com.google.android.permissioncontroller';
      await context.connect(NativePlatform.android);
      expect(context.defaultAppId, isNull);

      expect(
        await handleNativeApp(context, {'action': 'activate'}),
        _isToolError(contains('Pass appId')),
      );

      connector.foregroundAppValue = _app;
      await handleNativeGetElements(context);
      expect(context.defaultAppId, _app,
          reason: 'native_get_elements observes the foreground app');
    });

    test('an explicit appId becomes the default when none is known', () async {
      connector.foregroundAppValue = 'com.android.launcher3';
      await context.connect(NativePlatform.android);

      await handleNativeApp(
          context, {'action': 'activate', 'appId': 'com.android.settings'});
      expect(context.defaultAppId, isNull, reason: 'a system app');

      await handleNativeApp(context, {'action': 'activate', 'appId': _app});
      expect(context.defaultAppId, _app);
      expect(
        await handleNativePermissions(
            context, {'action': 'grant', 'permission': 'camera'}),
        _isToolSuccess(contains('for $_app')),
      );
    });

    test('is looked up lazily while unknown', () async {
      connector.foregroundAppValue = 'com.apple.springboard';
      await context.connect(NativePlatform.ios);
      expect(context.defaultAppId, isNull);

      connector.foregroundAppValue = _app;
      expect(
        await handleNativeApp(context, {'action': 'activate'}),
        _isToolSuccess('Activated $_app.'),
      );
    });

    test('native_wait_for observes the app it finds on screen', () async {
      connector.foregroundAppValue = 'com.apple.springboard';
      await context.connect(NativePlatform.ios);
      connector
        ..foregroundAppValue = _app
        ..onGetElements = (_) => [nativeElement(text: 'Request')];

      await handleNativeWaitFor(context, {'text': 'Request'});

      expect(context.defaultAppId, _app);
    });

    test('is cleared on disconnect', () async {
      await context.dispose();
      expect(context.defaultAppId, isNull);
      expect(context.platform, isNull);
    });
  });

  group('native_permissions', () {
    test('validates action and permission', () async {
      expect(
        await handleNativePermissions(
            context, {'action': 'allow', 'permission': 'camera'}),
        _isToolError(contains('"grant", "revoke" or "reset"')),
      );
      expect(
        await handleNativePermissions(
            context, {'action': 'grant', 'permission': 'bluetooth'}),
        _isToolError(contains('camera, microphone')),
      );
    });

    test('changes the permission of the default app', () async {
      final result = await handleNativePermissions(
        context,
        {'action': 'grant', 'permission': 'camera'},
      );

      expect(
          result,
          _isToolSuccess(
              'Granted camera (android.permission.CAMERA) for $_app.'));
      expect(device.calls, contains('permission grant camera $_app'));
    });

    test('reports notes and an app the change terminated', () async {
      device
        ..runningApps.add('com.other')
        ..permissionChangeKillsApp = true
        ..permissionChange = const NativePermissionChange(
          nativeNames: ['android.permission.CAMERA'],
          notes: ['Partial reset.'],
        );

      final result = await handleNativePermissions(context, {
        'action': 'revoke',
        'permission': 'camera',
        'appId': 'com.other',
      });

      expect(
        _text(result),
        allOf(
          contains('Revoked camera'),
          contains('Partial reset.'),
          contains('terminated com.other'),
          contains('Flutter'),
        ),
      );
    });

    test('platform errors keep their hint', () async {
      device.error = const NativeUnsupportedException(
        'No notifications on the simulator.',
        hint: 'Use native_tap.',
      );

      expect(
        await handleNativePermissions(
            context, {'action': 'grant', 'permission': 'notifications'}),
        _isToolError(contains('Hint: Use native_tap.')),
      );
    });
  });

  group('native_open_url', () {
    test('requires an absolute URL', () async {
      for (final url in [null, 'example.com', '']) {
        expect(
          await handleNativeOpenUrl(context, {'url': url}),
          _isToolError(contains('with a scheme')),
          reason: '$url',
        );
      }
    });

    test('opens the URL', () async {
      await handleNativeOpenUrl(
          context, {'url': 'marionette-example://app/testing'});
      expect(device.calls.last, 'openUrl marionette-example://app/testing');
    });

    test('on iOS a custom scheme mentions the "Open" confirmation', () async {
      await context.connect(NativePlatform.ios);

      expect(
        await handleNativeOpenUrl(context, {'url': 'myapp://x'}),
        _isToolSuccess(contains('text="Open"')),
      );
      expect(
        await handleNativeOpenUrl(context, {'url': 'https://x.y'}),
        _isToolSuccess(isNot(contains('text="Open"'))),
      );
    });
  });

  group('native_app', () {
    test('activate, terminate and restart use the default app', () async {
      expect(
        await handleNativeApp(context, {'action': 'activate'}),
        _isToolSuccess('Activated $_app.'),
      );
      expect(
        await handleNativeApp(context, {'action': 'terminate'}),
        _isToolSuccess(contains('Flutter lane connection')),
      );
      expect(
        await handleNativeApp(context, {'action': 'terminate'}),
        _isToolSuccess(startsWith('$_app was not running.')),
      );
      expect(
        await handleNativeApp(context, {'action': 'restart', 'appId': 'x.y'}),
        _isToolSuccess(contains('Restarted x.y')),
      );
      expect(device.calls, [
        'activate $_app',
        'terminate $_app',
        'terminate $_app',
        'terminate x.y',
        'activate x.y',
      ]);
    });

    test('restart on Android says to wait before a deep link', () async {
      final android =
          _text(await handleNativeApp(context, {'action': 'restart'}));
      await context.connect(NativePlatform.ios);
      final ios = _text(await handleNativeApp(context, {'action': 'restart'}));

      expect(android, contains('before native_open_url'));
      expect(ios, isNot(contains('native_open_url')));
    });

    test('terminate says Android also removed the notifications', () async {
      final android = _text(
        await handleNativeApp(context, {'action': 'terminate'}),
      );
      await context.connect(NativePlatform.ios);
      final ios = _text(
        await handleNativeApp(context, {'action': 'terminate'}),
      );

      expect(android, contains('notifications were removed'));
      expect(android, contains('action=background'));
      expect(ios, isNot(contains('notifications')));
    });

    test('background presses home', () async {
      await handleNativeApp(context, {'action': 'background'});
      expect(connector.pressedKeys, [NativeKey.home]);
    });

    test('rejects unknown actions', () async {
      expect(
        await handleNativeApp(context, {'action': 'launch'}),
        _isToolError(contains('"activate"')),
      );
    });
  });

  group('native_notifications', () {
    test('Android opens and closes the shade with commands', () async {
      await handleNativeNotifications(context, {'action': 'open'});
      await handleNativeNotifications(context, {'action': 'close'});
      expect(device.calls, ['openNotifications', 'closeNotifications']);
      expect(connector.swipes, isEmpty);
    });

    test('iOS swipes the Notification Center', () async {
      await context.connect(NativePlatform.ios);

      await handleNativeNotifications(context, {'action': 'open'});
      await handleNativeNotifications(context, {'action': 'close'});

      expect(connector.swipes, [
        (startX: 333, startY: 1, endX: 333, endY: 1200),
        // Up from the bottom edge: a swipe in the middle only scrolls the
        // notification list.
        (startX: 500, startY: 1999, endX: 500, endY: 1000),
      ]);
      expect(device.calls, isEmpty);
    });

    test('iOS says a notification opens with a swipe, Android does not',
        () async {
      final android =
          _text(await handleNativeNotifications(context, {'action': 'open'}));
      await context.connect(NativePlatform.ios);
      final ios =
          _text(await handleNativeNotifications(context, {'action': 'open'}));

      expect(android, isNot(contains('swipe it right')));
      expect(ios, contains('swipe it right with native_swipe'));
    });

    test('push builds an alert payload or takes a full one', () async {
      await handleNativeNotifications(
          context, {'action': 'push', 'title': 'Hi', 'body': 'There'});
      await handleNativeNotifications(context, {
        'action': 'push',
        'payload': {
          'aps': {'badge': 3},
        },
      });

      expect(device.calls, [
        'push $_app ${jsonEncode({
              'aps': {
                'alert': {'title': 'Hi', 'body': 'There'},
              },
            })}',
        'push $_app {"aps":{"badge":3}}',
      ]);
    });

    test('validates push arguments', () async {
      expect(
        await handleNativeNotifications(context, {'action': 'push'}),
        _isToolError(contains('title and/or body')),
      );
      expect(
        await handleNativeNotifications(context, {
          'action': 'push',
          'payload': {'alert': 'x'},
        }),
        _isToolError(contains('"aps"')),
      );
      expect(
        await handleNativeNotifications(context, {'action': 'show'}),
        _isToolError(contains('"open", "close" or "push"')),
      );
    });
  });

  group('device state', () {
    test('native_device_info combines device, screen and session', () async {
      final result = await handleNativeDeviceInfo(context);

      expect(jsonDecode(_text(result)), {
        'platform': 'android',
        'osVersion': 'Android 9',
        'apiLevel': 28,
        'model': 'Pixel 3',
        'isEmulator': true,
        'id': 'emulator-5554',
        'screen': {'width': 1000, 'height': 2000, 'scale': 1.0},
        'orientation': 'portrait',
        'foregroundApp': _app,
        'appId': _app,
      });
    });

    test('native_set_orientation rotates and validates', () async {
      expect(
        await handleNativeSetOrientation(context, {'orientation': 'Landscape'}),
        _isToolSuccess(contains('landscape')),
      );
      expect(connector.orientation, NativeOrientation.landscape);
      expect(
        await handleNativeSetOrientation(context, {'orientation': 'upside'}),
        _isToolError(contains('"portrait" or "landscape"')),
      );
    });

    test('native_set_location validates the range', () async {
      await handleNativeSetLocation(
          context, {'latitude': 52.23, 'longitude': 21.01});
      expect(device.calls.last, 'location 52.23,21.01');

      expect(
        await handleNativeSetLocation(
            context, {'latitude': 91, 'longitude': 0}),
        _isToolError(contains('-90..90')),
      );
    });
  });

  group('native_biometrics', () {
    test('passes the action to the device', () async {
      expect(
        await handleNativeBiometrics(context, {'action': 'match'}),
        _isToolSuccess(contains('Simulated a matching')),
      );
      expect(
        await handleNativeBiometrics(context, {'action': 'nonMatch'}),
        _isToolSuccess(contains('non-matching')),
      );
      await handleNativeBiometrics(context, {'action': 'enroll'});
      expect(device.calls, [
        'biometrics match',
        'biometrics nonMatch',
        'biometrics enroll',
      ]);
    });

    test('rejects unknown actions', () async {
      expect(
        await handleNativeBiometrics(context, {'action': 'touch'}),
        _isToolError(contains('"match", "nonMatch"')),
      );
    });
  });

  test('device tools tell the agent to connect first', () async {
    final disconnected = NativeServiceContext();
    for (final call in [
      () => handleNativePermissions(
          disconnected, {'action': 'grant', 'permission': 'camera'}),
      () => handleNativeOpenUrl(disconnected, {'url': 'https://x.y'}),
      () => handleNativeApp(disconnected, {'action': 'activate'}),
      () => handleNativeNotifications(disconnected, {'action': 'open'}),
      () => handleNativeDeviceInfo(disconnected),
      () =>
          handleNativeSetOrientation(disconnected, {'orientation': 'portrait'}),
      () => handleNativeSetLocation(
          disconnected, {'latitude': 1, 'longitude': 1}),
      () => handleNativeBiometrics(disconnected, {'action': 'match'}),
    ]) {
      expect(await call(), _isToolError(contains('native_connect')));
    }
  });
}
