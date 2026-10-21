@Tags(['device'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

/// The permission scenario driven by `marionette native-*` commands (device
/// setup with adb / simctl) against the example app on an emulator or
/// simulator. Run with `dart test -P device`; set
/// `MARIONETTE_E2E_PLATFORM=ios` (and `MARIONETTE_E2E_UDID` /
/// `MARIONETTE_E2E_SERIAL` when several devices are connected).
const _app = 'com.example.counter';
const _link = 'marionette-example://app/testing/permission-dialogs';

void main() {
  final env = Platform.environment;
  final platform = env['MARIONETTE_E2E_PLATFORM'] ?? 'android';
  final serial = env['MARIONETTE_E2E_SERIAL'];
  final udid = env['MARIONETTE_E2E_UDID'];
  const session = ['--native-session', 'e2e'];
  late String marionette;

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('marionette_cli_e2e_');
    marionette = '${dir.path}/marionette';
    final compiled = await Process.run(
      Platform.resolvedExecutable,
      ['compile', 'exe', 'bin/marionette.dart', '-o', marionette],
    );
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });

  /// Runs `marionette --native-session e2e <args>` and expects [exitCode].
  Future<String> run(List<String> args, {int exitCode = 0}) async {
    final result = await Process.run(marionette, [...session, ...args]);
    final output = '${result.stdout}${result.stderr}';
    expect(
      result.exitCode,
      exitCode,
      reason: 'marionette ${args.join(' ')}:\n$output',
    );
    return output;
  }

  tearDownAll(() async {
    await Process.run(marionette, [...session, 'native-disconnect']);
  });

  test('permission dialog only from the CLI', () async {
    await run([
      'native-connect',
      '--platform',
      platform,
      if (serial != null) ...['--serial', serial],
      if (udid != null) ...['--udid', udid],
    ]);
    expect(await run(['native-sessions']), contains('e2e\t$platform'));

    // Device setup outside Marionette: reset the camera permission, start
    // the app and open the screen by deep link.
    final adb = [
      'adb',
      if (serial != null) ...['-s', serial]
    ];
    final simulator = udid ?? 'booted';
    for (final command in platform == 'android'
        ? [
            [
              ...adb,
              'shell',
              'pm',
              'revoke',
              _app,
              'android.permission.CAMERA'
            ],
            [
              ...adb, 'shell', 'monkey', '-p', _app, '-c', //
              'android.intent.category.LAUNCHER', '1',
            ],
          ]
        : [
            ['xcrun', 'simctl', 'privacy', simulator, 'reset', 'camera', _app],
            ['xcrun', 'simctl', 'launch', simulator, _app],
          ]) {
      final result = await Process.run(command.first, command.skip(1).toList());
      expect(result.exitCode, 0, reason: '$command: ${result.stderr}');
    }
    // A deep link sent while the app starts is lost on Android: send it
    // again until the screen shows.
    for (var attempt = 1;; attempt++) {
      final link = await Process.run(
        platform == 'android' ? adb.first : 'xcrun',
        platform == 'android'
            ? [
                ...adb.skip(1), 'shell', 'am', 'start', '-a', //
                'android.intent.action.VIEW', '-d', "'$_link'", _app,
              ]
            : ['simctl', 'openurl', simulator, _link],
      );
      expect(link.exitCode, 0, reason: '${link.stderr}');
      final shown = await Process.run(marionette, [
        ...session, 'native-wait-for', '--text-contains', 'Camera access', //
        '--timeout-ms', '8000',
      ]);
      if (shown.exitCode == 0) break;
      expect(attempt, lessThan(3), reason: '${shown.stderr}');
    }
    await run(['native-tap', '--text', 'Request', '--index', '0']);

    final allow = platform == 'android'
        ? ['--text-contains', 'While using', '--type', 'android.widget.Button']
        : ['--text', 'Allow', '--type', 'XCUIElementTypeButton'];
    await run(['native-wait-for', ...allow, '--timeout-ms', '10000']);
    await run(['native-tap', ...allow]);
    await run(
        ['native-wait-for', '--text-contains', 'Camera access · granted']);

    // A missing element fails with the shared message and exit code 1.
    final missing = await run(
      ['native-tap', '--text', 'No such element'],
      exitCode: 1,
    );
    expect(missing, contains('native-get-elements'));
  });
}
