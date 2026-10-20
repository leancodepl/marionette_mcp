import 'dart:io';

import 'package:marionette_cli/src/cli/native_doctor.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late NativeSessionRegistry registry;
  late Map<String, ProcessResult Function()> outputs;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('marionette_doctor_');
    registry = NativeSessionRegistry(baseDir: '${tempDir.path}/native');
    outputs = {
      'adb version': () => _ok('Android Debug Bridge version 1.0.41\n'),
      'adb devices': () => _ok('List of devices attached\n'),
      'ps -axo pid=,ppid=,command=': () => _ok(''),
      'xcrun simctl list devices booted -j': () => _ok('{"devices": {}}'),
    };
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  NativeDoctor doctor({
    bool isMacOS = false,
    Map<String, String> environment = const {},
    bool serversRunning = true,
    bool portFree = true,
  }) =>
      NativeDoctor(
        registry: registry,
        processRunner: (executable, arguments) async {
          final key = [executable, ...arguments].join(' ');
          final output = outputs[key];
          if (output == null) {
            throw ProcessException(executable, arguments, 'not found');
          }
          return output();
        },
        environment: environment,
        isMacOS: isMacOS,
        uia2CacheDir: Directory('${tempDir.path}/uia2'),
        wdaCacheDir: Directory('${tempDir.path}/wda'),
        isServerRunning: (_) async => serversRunning,
        isPortFree: (_) async => portFree,
      );

  List<String> lines(List<DoctorFinding> findings) => [
        for (final f in findings)
          '${f.status.name}: ${f.message}${f.fix == null ? '' : ' | ${f.fix}'}',
      ];

  test('reports adb, devices by state and the UIAutomator2 cache', () async {
    outputs['adb devices'] = () => _ok(
          'List of devices attached\n'
          'emulator-5554\tdevice\n'
          'R58M\tunauthorized\n'
          'emulator-5556\toffline\n',
        );

    final report = lines(await doctor().check());

    expect(report, [
      'ok: Android Debug Bridge version 1.0.41',
      'ok: Android device emulator-5554',
      'problem: Android device R58M is unauthorized. | Accept the USB '
          'debugging prompt on the device.',
      'problem: Android device emulator-5556 is offline. | Run "adb '
          'reconnect", or restart the device / emulator.',
      startsWith('note: UIAutomator2 10.3.2 is not cached yet'),
    ]);
  });

  test('UIAutomator2: a cached APK with the wrong checksum, overrides',
      () async {
    final cache = Directory('${tempDir.path}/uia2')..createSync();
    for (final name in [
      'appium-uiautomator2-server-v10.3.2.apk',
      'appium-uiautomator2-server-debug-androidTest.apk',
    ]) {
      File('${cache.path}/$name').writeAsStringSync('not an apk');
    }

    expect(
      lines(await doctor().check()),
      contains(startsWith('note: A cached UIAutomator2 APK does not match')),
    );
    expect(
      lines(
        await doctor(
          environment: {'MARIONETTE_UIA2_SERVER_APK': '/missing.apk'},
        ).check(),
      ),
      contains(
        'problem: MARIONETTE_UIA2_SERVER_APK points to a missing file: '
        '/missing.apk | Fix or unset MARIONETTE_UIA2_SERVER_APK.',
      ),
    );
  });

  test('a missing adb is only a note', () async {
    outputs.remove('adb version');

    final report = lines(await doctor().check());

    expect(report.first, startsWith('note: adb not found'));
  });

  test('macOS: booted simulators and the WebDriverAgent build', () async {
    outputs['xcrun simctl list devices booted -j'] = () => _ok('''
{"devices": {"iOS-26-4": [{"state": "Booted", "udid": "SIM-A"}]}}''');
    Directory('${tempDir.path}/wda/Build').createSync(recursive: true);
    File('${tempDir.path}/wda/Build/WDA.xctestrun').createSync();

    final report = lines(await doctor(isMacOS: true).check());

    expect(report, contains('ok: iOS Simulator SIM-A'));
    expect(report, contains(startsWith('ok: WebDriverAgent built in')));
  });

  test('macOS: a missing WDA build and a broken variable', () async {
    expect(
      lines(await doctor(isMacOS: true).check()),
      contains(startsWith('note: No prebuilt WebDriverAgent')),
    );
    expect(
      lines(
        await doctor(
          isMacOS: true,
          environment: {'MARIONETTE_WDA_XCTESTRUN': '/missing.xctestrun'},
        ).check(),
      ),
      contains(startsWith('problem: MARIONETTE_WDA_XCTESTRUN points to')),
    );
  });

  test('macOS: WebDriverAgent from MARIONETTE_WDA_BUNDLE / _PATH', () async {
    final bundle = Directory('${tempDir.path}/WebDriverAgentRunner-Runner.app')
      ..createSync();

    expect(
      lines(
        await doctor(
          isMacOS: true,
          environment: {'MARIONETTE_WDA_BUNDLE': bundle.path},
        ).check(),
      ),
      contains('ok: WebDriverAgent (MARIONETTE_WDA_BUNDLE): ${bundle.path}'),
    );
    expect(
      lines(
        await doctor(
          isMacOS: true,
          environment: {'MARIONETTE_WDA_PATH': '/missing'},
        ).check(),
      ),
      contains(startsWith('problem: MARIONETTE_WDA_PATH points to a missing')),
    );
  });

  test('macOS: port 8100 taken by something that is not WebDriverAgent',
      () async {
    expect(
      lines(
        await doctor(isMacOS: true, portFree: false, serversRunning: false)
            .check(),
      ),
      contains(startsWith('problem: Port 8100, which WebDriverAgent needs')),
    );
    expect(
      lines(await doctor(isMacOS: true, portFree: false).check())
          .where((line) => line.contains('Port 8100')),
      isEmpty,
      reason: 'a running WebDriverAgent is not a conflict',
    );
  });

  test('servers: owned by a session, held by a process, or orphaned', () async {
    registry.save(
      NativeSessionInfo(
        name: 'pixel',
        platform: 'android',
        baseUrl: 'http://127.0.0.1:8200',
        createdAt: DateTime.utc(2026, 10, 20),
        serial: 'emulator-5554',
        pid: 101,
      ),
    );
    outputs['ps -axo pid=,ppid=,command='] = () => _ok(
          '  101     1 adb -s emulator-5554 shell am instrument -w -e '
          'disableAnalytics true io.appium.uiautomator2.server.test/x\n'
          '  202   555 xcodebuild test-without-building -xctestrun '
          '/c/WebDriverAgentRunner_iphonesimulator.xctestrun\n'
          '  303     1 xcodebuild test-without-building -xctestrun '
          '/c/WebDriverAgentRunner_iphonesimulator.xctestrun\n'
          '  404     1 /usr/bin/some-other-process\n',
        );

    final report = lines(await doctor().check());

    expect(
        report,
        contains('ok: UIAutomator2 (pid 101) of native session '
            '"pixel"'));
    expect(
        report,
        contains(startsWith('ok: WebDriverAgent (pid 202) held by '
            'process 555')));
    expect(
        report,
        contains(startsWith('problem: Orphaned WebDriverAgent '
            '(pid 303)')));
    expect(report.where((line) => line.contains('404')), isEmpty);
  });

  test('a session whose server is gone is a problem with a fix', () async {
    registry.save(
      NativeSessionInfo(
        name: 'iphone',
        platform: 'ios',
        baseUrl: 'http://127.0.0.1:8100',
        createdAt: DateTime.utc(2026, 10, 20),
        udid: 'SIM-A',
      ),
    );

    final report = lines(await doctor(serversRunning: false).check());

    expect(
      report.last,
      'problem: Native session "iphone" (ios, SIM-A): its server is not '
      'running. | marionette --native-session iphone native-connect '
      '--platform ios, or native-disconnect to forget it.',
    );
  });
}

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
