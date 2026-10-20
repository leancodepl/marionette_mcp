@Tags(['device'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

/// The plan's CLI acceptance (D-01): the §3 permission scenario driven only
/// by `marionette native-*` commands against the example app on an emulator
/// or simulator. Run with `dart test -P device`; set
/// `MARIONETTE_E2E_PLATFORM=ios` (and `MARIONETTE_E2E_UDID` /
/// `MARIONETTE_E2E_SERIAL` when several devices are connected).
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

  test('§3 permission dialog only from the CLI', () async {
    await run([
      'native-connect',
      '--platform',
      platform,
      if (serial != null) ...['--serial', serial],
      if (udid != null) ...['--udid', udid],
    ]);
    expect(await run(['native-sessions']), contains('e2e\t$platform'));

    await run([
      'native-permissions',
      '--action', 'reset', //
      '--permission', 'camera',
      '--app-id', 'com.example.counter',
    ]);
    await run(['native-app', '--action', 'activate']);
    // A deep link sent while the app starts is lost on Android (D11).
    await run(['native-wait-for', '--text-contains', 'Tab 1 of 4']);
    await run([
      'native-open-url',
      '--url',
      'marionette-example://app/testing/device',
    ]);
    await run(['native-wait-for', '--text', 'Request camera']);
    await run(
        ['native-scroll', '--direction', 'up', '--text', 'Request camera']);
    await run(['native-tap', '--text', 'Request camera']);

    final allow = platform == 'android'
        ? ['--text-contains', 'While using', '--type', 'android.widget.Button']
        : ['--text', 'Allow', '--type', 'XCUIElementTypeButton'];
    await run(['native-wait-for', ...allow, '--timeout-ms', '10000']);
    await run(['native-tap', ...allow]);
    await run(['native-wait-for', '--text-contains', 'camera: granted']);

    // A missing element fails with the shared message and exit code 1.
    final missing = await run(
      ['native-tap', '--text', 'No such element'],
      exitCode: 1,
    );
    expect(missing, contains('native-get-elements'));
  });
}
