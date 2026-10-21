@Tags(['device'])
@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';

import 'support/e2e_harness.dart';

/// End-to-end scenarios of the native lane: the real MCP server over
/// stdio against the example app on an emulator or simulator. Excluded from
/// a plain `dart test`; run them with
///
/// ```sh
/// dart test -P device                       # Android (adb device)
/// MARIONETTE_E2E_PLATFORM=ios dart test -P device
/// ```
///
/// The example app must be installed; see [E2eConfig] for the environment.
void main() {
  final config = E2eConfig.fromEnvironment();
  late McpTestClient client;

  setUpAll(() async {
    print('E2E artifacts: ${config.artifacts.path}');
    client = await McpTestClient.start(config.artifacts);
    await client.ok('native_connect', config.connectArgs);
    await config.launchApp();
  });

  tearDownAll(() async {
    await client.call('native_disconnect');
    await client.close();
  });

  /// Brings the app to the front and opens [route] by deep link. A link sent
  /// while the app is still starting is lost on Android, so it is sent again
  /// until [waitFor] appears.
  Future<void> openScreen(String route, {required String waitFor}) async {
    await config.launchApp();
    for (var attempt = 1;; attempt++) {
      await config.openUrl('marionette-example://app$route');
      final shown = await client.call('native_wait_for', {
        'textContains': waitFor,
        'timeoutMs': 8000,
      });
      if (!shown.isError) return;
      if (attempt == 3) fail('$route did not open: ${shown.text}');
    }
  }

  void scenario(
    String name,
    Future<void> Function() body, {
    Object? skip,
  }) =>
      test(
        name,
        () => withArtifacts(client, config, name, body),
        skip: skip,
      );

  // First: later scenarios may restart the app (a permission reset does
  // on iOS), which ends the VM service of `flutter run`.
  scenario(
    'both lanes: the Flutter lane warns when native UI covers the app',
    () async {
      await client.ok('connect', {'uri': config.vmServiceUri});
      await openScreen('/testing/native-dialogs', waitFor: 'Show native alert');

      await client.ok('native_tap', {'text': 'Show native alert'});
      await client.ok('native_wait_for', {'id': 'android:id/button1'});
      final covered = await client.ok('get_interactive_elements');
      expect(covered.text, contains('the app is not in front'));
      await client.ok('native_tap', {'id': 'android:id/button1'});
    },
    skip: config.vmServiceUri == null
        ? 'Set MARIONETTE_E2E_VM_SERVICE_URI (flutter run) for this scenario'
        : config.isIos
            ? 'An alert of the app leaves iOS resumed'
            : null,
  );

  scenario('native controls: type into and tap a native view', () async {
    await openScreen(
      '/testing/platform-views/native-controls',
      waitFor: 'Tap me (native)',
    );

    await client.ok('native_enter_text', {
      'label': 'Type here (native)',
      'text': 'Zażółć',
      'clear': true,
    });
    final field = await client.ok('native_get_elements', {
      'textContains': 'Type here',
      'includeForegroundApp': false,
    });
    expect(field.text, contains('"value":"Zażółć"'));

    final before = await client.ok('native_get_elements', {
      'textContains': 'Native button taps',
      'includeForegroundApp': false,
    });
    final count = int.parse(
      RegExp(r'Native button taps: (\d+)').firstMatch(before.text)!.group(1)!,
    );
    await client.ok('native_tap', {'text': 'Tap me (native)'});
    await client.ok('native_wait_for', {
      'text': 'Native button taps: ${count + 1}',
    });
  });

  scenario('permission dialog: reset, ask and allow camera', () async {
    // Resetting may terminate the app (iOS); openScreen starts it again.
    await config.resetCameraPermission();
    await openScreen('/testing/permission-dialogs', waitFor: 'Camera access');
    await client.ok('native_tap', {'text': 'Request', 'index': 0});

    final allow = config.isAndroid
        ? {'textContains': 'While using', 'type': 'android.widget.Button'}
        : {'text': 'Allow', 'type': 'XCUIElementTypeButton'};
    await client.ok('native_wait_for', {...allow, 'timeoutMs': 10000});
    await client.ok('native_tap', allow);
    await client.ok('native_wait_for', {
      'textContains': 'Camera access · granted',
    });
  });

  scenario('native alert: shown by the app, answered natively', () async {
    await openScreen('/testing/native-dialogs', waitFor: 'Show native alert');
    await client.ok('native_tap', {'text': 'Show native alert'});

    final ok = config.isAndroid
        ? {'id': 'android:id/button1'}
        : {'text': 'OK', 'type': 'XCUIElementTypeButton'};
    await client.ok('native_wait_for', ok);
    await client.ok('native_tap', ok);
    await client.ok('native_wait_for', {'text': 'Alert result: ok'});
  });

  scenario('keyboard: type, edit with keys, read the value', () async {
    await openScreen('/testing/keyboard', waitFor: 'Title');
    await client.ok('native_enter_text', {
      'label': 'Title',
      'text': 'e2e!',
      'clear': true,
    });
    await client.ok('native_press_key', {'key': 'backspace'});
    if (config.isIos) {
      // Software keyboard keys are elements on iOS.
      await client.ok('native_tap', {
        'text': 'x',
        'type': 'XCUIElementTypeKey',
      });
    } else {
      await client.ok('native_enter_text', {'text': 'x'});
    }
    // A focused Flutter field on iOS reports its hint as a second line.
    final title = await client.ok('native_get_elements', {
      'textContains': 'Title',
      'includeForegroundApp': false,
    });
    expect(title.text, contains('"value":"e2ex"'));
  });
}
