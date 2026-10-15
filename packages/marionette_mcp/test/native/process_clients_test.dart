import 'dart:io';

import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/process.dart';
import 'package:marionette_mcp/src/native_service/simctl_client.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';

void main() {
  group('processMessage', () {
    test('prefers stderr, then stdout, then exit code', () {
      expect(processMessage(failed(stderr: ' boom ', stdout: 'out')), 'boom');
      expect(processMessage(failed(stdout: ' out ')), 'out');
      expect(
        processMessage(failed(exitCode: 3)),
        'process exited with code 3',
      );
    });
  });

  group('checkProcessResult', () {
    test('passes on exit code 0', () {
      expect(
          () => checkProcessResult(ok(), 'xcrun', ['simctl']), returnsNormally);
    });

    test('throws ProcessCommandException with command and output', () {
      expect(
        () => checkProcessResult(
          failed(exitCode: 2, stderr: 'nope'),
          'xcrun',
          ['simctl', 'list'],
        ),
        throwsA(
          isA<ProcessCommandException>()
              .having((e) => e.command, 'command', 'xcrun simctl list')
              .having((e) => e.exitCode, 'exitCode', 2)
              .having((e) => e.toString(), 'toString', contains('nope')),
        ),
      );
    });
  });

  group('AdbClient', () {
    test('prefixes every command with -s serial', () async {
      final runner = FakeProcessRunner();
      final adb =
          AdbClient(serial: 'emulator-5554', processRunner: runner.call);

      await adb.run(['devices']);
      await adb.shell(['getprop']);

      expect(runner.calls.map((c) => c.arguments), [
        ['-s', 'emulator-5554', 'devices'],
        ['-s', 'emulator-5554', 'shell', 'getprop'],
      ]);
    });

    test('omits device selection without a serial', () {
      expect(AdbClient().argumentsFor(['devices']), ['devices']);
    });

    test('foregroundPackage reports the focused window package', () async {
      final runner = FakeProcessRunner()
        ..onAdb(
          ['shell', 'dumpsys', 'window', 'windows'],
          result: ok(
            '  mCurrentFocus=Window{1a2b u0 com.google.android.permissioncontroller/'
            'com.android.permissioncontroller.permission.ui.GrantPermissionsActivity}\n'
            '  mFocusedApp=ActivityRecord{3c4d u0 com.example.app/.MainActivity t5}\n',
          ),
        );

      expect(
        await AdbClient(processRunner: runner.call).foregroundPackage(),
        'com.google.android.permissioncontroller',
      );
    });

    test('foregroundPackage prefers dumpsys window displays (Android 10+)',
        () async {
      final runner = FakeProcessRunner()
        ..onAdb(
          ['shell', 'dumpsys', 'window', 'displays'],
          result:
              ok('  mCurrentFocus=Window{c35 u0 com.android.launcher/.Home}'),
        );

      expect(
        await AdbClient(processRunner: runner.call).foregroundPackage(),
        'com.android.launcher',
      );
      expect(runner.adbCommands, [
        ['shell', 'dumpsys', 'window', 'displays'],
      ]);
    });

    test('foregroundPackage returns null instead of throwing', () async {
      final failing = FakeProcessRunner()
        ..failExecutable('adb', const ProcessException('adb', [], 'missing'));
      final nonZero = FakeProcessRunner()
        ..onAdb(['shell'], result: failed(stderr: 'error'));

      expect(
        await AdbClient(processRunner: failing.call).foregroundPackage(),
        isNull,
      );
      expect(
        await AdbClient(processRunner: nonZero.call).foregroundPackage(),
        isNull,
      );
    });
  });

  group('parseForegroundPackage', () {
    test('falls back to mFocusedApp', () {
      expect(
        parseForegroundPackage(
          'mFocusedApp=ActivityRecord{48377e2 u0 com.example.app/.MainActivity t62}',
        ),
        'com.example.app',
      );
    });

    test('returns null for unrelated output', () {
      expect(parseForegroundPackage('nothing here'), isNull);
    });
  });

  group('SimctlClient', () {
    test('listBootedUdids parses booted devices only', () async {
      final runner = FakeProcessRunner()
        ..on(
          'xcrun',
          ['simctl', 'list', 'devices', 'booted', '-j'],
          result: ok('''
{"devices": {
  "iOS-17": [{"state": "Shutdown", "udid": "OFF"}],
  "iOS-18": [{"state": "Booted", "udid": "ON-1"}, {"state": "Booted", "udid": "ON-2"}]
}}'''),
        );

      expect(
        await SimctlClient(processRunner: runner.call).listBootedUdids(),
        ['ON-1', 'ON-2'],
      );
    });

    test('listBootedUdids throws on non-zero exit and bad JSON', () async {
      final failing = FakeProcessRunner()
        ..on('xcrun', ['simctl'], result: failed(stderr: 'broken'));
      final garbage = FakeProcessRunner()
        ..on('xcrun', ['simctl'], result: ok('[]'));

      await expectLater(
        SimctlClient(processRunner: failing.call).listBootedUdids(),
        throwsA(isA<ProcessCommandException>()),
      );
      await expectLater(
        SimctlClient(processRunner: garbage.call).listBootedUdids(),
        throwsA(isA<FormatException>()),
      );
    });

    test('install, launch and terminate call simctl and check the result',
        () async {
      final runner = FakeProcessRunner();
      final simctl = SimctlClient(processRunner: runner.call);

      await simctl.install('UDID', '/tmp/WDA.app');
      await simctl.launch('UDID', 'com.wda');
      await simctl.terminate('UDID', 'com.wda');

      expect(runner.calls.map((c) => c.arguments), [
        ['simctl', 'install', 'UDID', '/tmp/WDA.app'],
        ['simctl', 'launch', 'UDID', 'com.wda'],
        ['simctl', 'terminate', 'UDID', 'com.wda'],
      ]);

      runner.on('xcrun', ['simctl', 'launch'], result: failed(stderr: 'no'));
      await expectLater(
        simctl.launch('UDID', 'com.wda'),
        throwsA(isA<ProcessCommandException>()),
      );
    });
  });
}
