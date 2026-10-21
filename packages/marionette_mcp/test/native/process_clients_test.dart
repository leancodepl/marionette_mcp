import 'dart:io';

import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/process.dart';
import 'package:marionette_mcp/src/native_service/simctl_client.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';

void main() {
  group('canBindLoopbackPort', () {
    test('a port nobody uses is free', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();

      expect(await canBindLoopbackPort(port), isTrue);
    });

    test('a port a dual-stack server listens on is taken', () async {
      // Seen on macOS: 127.0.0.1 could be bound while `python3 -m
      // http.server 8100` (IPv6 *) listened, so 8100 was reported free.
      final server = await ServerSocket.bind(
        InternetAddress.anyIPv6,
        0,
        v6Only: false,
      );
      addTearDown(server.close);
      server.listen((client) => client.destroy());

      expect(await canBindLoopbackPort(server.port), isFalse);
    });
  });

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

  group('AdbClient device queries', () {
    test('resolveSerial prefers the configured serial', () async {
      final runner = FakeProcessRunner();

      expect(
        await AdbClient(serial: 'X', processRunner: runner.call)
            .resolveSerial(),
        'X',
      );
      expect(runner.calls, isEmpty);
    });

    test('resolveSerial asks adb for the default device', () async {
      final runner = FakeProcessRunner()
        ..onAdb(['get-serialno'], result: ok('emulator-5556\n'));

      expect(
        await AdbClient(processRunner: runner.call).resolveSerial(),
        'emulator-5556',
      );
    });

    test('forwardedLocalPort lists forwards of all devices', () async {
      final runner = FakeProcessRunner()
        ..on(
          'adb',
          ['forward', '--list'],
          result: ok(
            'emulator-5554 tcp:8200 tcp:6790\n'
            'emulator-5556 tcp:8201 tcp:6790\n',
          ),
        );
      final adb =
          AdbClient(serial: 'emulator-5556', processRunner: runner.call);

      expect(await adb.forwardedLocalPort('emulator-5556', 6790), 8201);
      expect(runner.calls.single.arguments, ['forward', '--list']);
    });

    test('installedApkSha256 hashes the installed base APK', () async {
      const hash =
          '8463a42f7701bf29d07571089e189ff10178c5f6dab2b65ae8cce7018d44fbd8';
      final runner = FakeProcessRunner()
        ..onAdb(
          ['shell', 'pm', 'path', 'io.appium.uiautomator2.server'],
          result: ok('package:/data/app/~~a==/io.appium-1/base.apk\n'),
        )
        ..onAdb(
          ['shell', 'sha256sum', '/data/app/~~a==/io.appium-1/base.apk'],
          result: ok('${hash.toUpperCase()}  /data/app/base.apk\n'),
        );

      expect(
        await AdbClient(processRunner: runner.call)
            .installedApkSha256('io.appium.uiautomator2.server'),
        hash,
      );
    });

    test('installedApkSha256 returns null for a missing package', () async {
      final runner = FakeProcessRunner()
        ..onAdb(['shell', 'pm', 'path'], result: failed());

      expect(
        await AdbClient(processRunner: runner.call)
            .installedApkSha256('com.missing'),
        isNull,
      );
    });
  });

  group('parseForwardedLocalPort', () {
    test('matches serial and remote port exactly', () {
      const list = 'emulator-5554 tcp:9000 tcp:1234\n'
          'emulator-5554 tcp:8200 tcp:6790\n'
          'emulator-55540 tcp:8300 tcp:6790\n';

      expect(
        parseForwardedLocalPort(
          list,
          deviceSerial: 'emulator-5554',
          remotePort: 6790,
        ),
        8200,
      );
      expect(
        parseForwardedLocalPort(list, deviceSerial: 'other', remotePort: 6790),
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

    test('the notification shade is SystemUI, not the app below', () {
      // API 35 with the shade open; older versions name it StatusBar.
      const shade = '''
  mCurrentFocus=Window{6bb05b2 u0 NotificationShade}
  mFocusedApp=ActivityRecord{dc111be u0 com.example.counter/.MainActivity t110}''';

      expect(parseForegroundPackage(shade), 'com.android.systemui');
      expect(
        parseForegroundPackage(
            shade.replaceAll('NotificationShade', 'StatusBar')),
        'com.android.systemui',
      );
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

  group('parseCurrentUserLocked', () {
    // Seen on API 35 after a restart of an emulator with a PIN: UIAutomator2
    // failed with "Package ... is not encryption aware".
    const dumpsys = '''
Current user: 0

Users:
  UserInfo{0:null:4c13} serialNo=0 isPrimary=true
    Type: android.os.usertype.full.SYSTEM
    State: RUNNING_LOCKED
  UserInfo{10:Guest:c13} serialNo=10
    State: RUNNING_UNLOCKED
''';

    test('the current user locked after a restart', () {
      expect(parseCurrentUserLocked(dumpsys), isTrue);
    });

    test('an unlocked current user, another user or no data', () {
      expect(
        parseCurrentUserLocked(
          dumpsys.replaceFirst('RUNNING_LOCKED', 'RUNNING_UNLOCKED'),
        ),
        isFalse,
      );
      expect(
        parseCurrentUserLocked(
          dumpsys.replaceFirst('Current user: 0', 'Current user: 10'),
        ),
        isFalse,
      );
      expect(parseCurrentUserLocked(''), isFalse);
    });
  });

  group('parseKeyboardCoverage', () {
    test('floating toolbar covers nothing, a full keyboard a large part', () {
      expect(
        parseKeyboardCoverage('''
  Window #7 Window{ad0968f u0 InputMethod}:
    Requested w=1280 h=2700 mLayoutSeq=577
    mGivenContentInsets=[0,2700][0,0] mGivenVisibleInsets=[0,2700][0,0]
'''),
        0,
      );
      expect(
        parseKeyboardCoverage('''
  Window #6 Window{a1 u0 InputMethod}:
    Requested w=1080 h=2028 mLayoutSeq=12
    mGivenContentInsets=[0,1215][0,0]
  Window #7 Window{b2 u0 com.example/.Main}:
    mGivenContentInsets=[0,0][0,0]
'''),
        closeTo(0.4, 0.01),
      );
      expect(parseKeyboardCoverage('no ime here'), isNull);
    });
  });
}
