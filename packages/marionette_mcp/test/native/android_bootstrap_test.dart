import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';
import 'support/fake_webdriver_server.dart';

void main() {
  _portSelectionTests();

  group('AndroidBootstrap', () {
    late Directory cacheDir;
    late FakeWebDriverServer server;
    late FakeProcessRunner runner;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('marionette_uia2_');
      server = await FakeWebDriverServer.start();
      runner = FakeProcessRunner()
        ..onAdb(['version'], result: ok('1.0.41'))
        ..onAdb(['get-state'], result: ok('device'))
        ..onAdb(['install'], result: ok('Success'));
    });

    tearDown(() async {
      await server.close();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    });

    AndroidBootstrap bootstrap({
      String? serial,
      ApkDownloader? downloader,
      int? localPort,
      bool explicitPort = true,
      Map<String, String> environment = const {},
      Map<String, String> apkSha256 = const {},
      PortProbe? isPortFree,
    }) =>
        AndroidBootstrap(
          serial: serial,
          processRunner: runner.call,
          downloader: downloader ?? (_) async => [1],
          cacheDir: cacheDir,
          localPort: explicitPort ? (localPort ?? server.port) : null,
          environment: environment,
          apkSha256: apkSha256,
          isPortFree: isPortFree ?? (_) async => true,
        );

    List<List<String>> installs() =>
        runner.adbCommands.where((cmd) => cmd.first == 'install').toList();

    Matcher failsWith(AndroidBootstrapFailure failure) => throwsA(
          isA<AndroidBootstrapException>()
              .having((e) => e.failure, 'failure', failure)
              .having((e) => e.hint, 'hint', failure.hint),
        );

    test('missing adb throws AndroidBootstrapException(adbMissing)', () async {
      runner.failExecutable(
        'adb',
        const ProcessException('adb', [], 'No such file or directory', 2),
      );

      await expectLater(
        bootstrap().ensureServerReady(),
        throwsA(
          isA<AndroidBootstrapException>()
              .having(
                (e) => e.failure,
                'failure',
                AndroidBootstrapFailure.adbMissing,
              )
              .having((e) => e.message, 'message', contains('adb')),
        ),
      );
    });

    test('device not online throws deviceUnavailable', () async {
      runner.onAdb(
        ['get-state'],
        result: failed(stdout: 'offline', stderr: 'error: device offline'),
      );

      await expectLater(
        bootstrap().ensureServerReady(),
        failsWith(AndroidBootstrapFailure.deviceUnavailable),
      );
    });

    test('a device locked after a restart fails at once with deviceLocked',
        () async {
      runner.onAdb(
        ['shell', 'dumpsys', 'user'],
        result: ok('Current user: 0\n  UserInfo{0:null:4c13}\n'
            '    State: RUNNING_LOCKED\n'),
      );

      await expectLater(
        bootstrap().ensureServerReady(),
        failsWith(AndroidBootstrapFailure.deviceLocked),
      );
      expect(
        runner.adbCommands.where((c) => c.contains('instrument')),
        isEmpty,
        reason: 'UIAutomator2 is not started on a locked device',
      );
    });

    test(
      'ensureServerReady installs, instruments, forwards, and becomes healthy',
      () async {
        final downloadedUrls = <Uri>[];
        final subject = bootstrap(
          serial: 'emulator-5554',
          downloader: (url) async {
            downloadedUrls.add(url);
            return [0x50, 0x4B, 0x03, 0x04]; // minimal zip/apk-ish bytes
          },
        );

        final uri = await subject.ensureServerReady();
        expect(uri.port, server.port);
        expect(uri.host, '127.0.0.1');

        expect(downloadedUrls, hasLength(2));
        expect(
          downloadedUrls.every(
            (u) => u.path.contains('appium-uiautomator2-server'),
          ),
          isTrue,
        );

        final commands = runner.adbCommands
            .where(
              (cmd) =>
                  cmd.first == 'install' ||
                  (cmd.first == 'forward' && cmd[1] != '--list') ||
                  (cmd.length >= 3 &&
                      cmd[0] == 'shell' &&
                      cmd[2] == 'instrument'),
            )
            .toList();

        expect(commands[0].take(3).toList(), ['install', '-r', '-t']);
        expect(commands[1].take(3).toList(), ['install', '-r', '-t']);
        expect(commands[2], [
          'shell',
          'am',
          'instrument',
          '-e',
          'disableAnalytics',
          'true',
          'io.appium.uiautomator2.server.test/'
              'androidx.test.runner.AndroidJUnitRunner',
        ]);
        expect(commands[3], ['forward', 'tcp:${server.port}', 'tcp:6790']);

        // Serial is threaded into every device-specific adb invocation
        // (`forward --list` lists all devices).
        expect(
          runner.calls
              .where((call) => !call.arguments.contains('--list'))
              .every(
                (call) =>
                    call.arguments.length >= 2 &&
                    call.arguments[0] == '-s' &&
                    call.arguments[1] == 'emulator-5554',
              ),
          isTrue,
        );

        await subject.dispose();
        expect(
          runner.adbCommands,
          containsAll([
            ['shell', 'am', 'force-stop', 'io.appium.uiautomator2.server.test'],
            ['forward', '--remove', 'tcp:${server.port}'],
          ]),
        );
      },
    );

    test('reuses cached APKs instead of downloading again', () async {
      var downloads = 0;
      Future<List<int>> downloader(Uri _) async {
        downloads++;
        return [1, 2, 3];
      }

      await bootstrap(downloader: downloader).ensureServerReady();
      await bootstrap(downloader: downloader).ensureServerReady();

      expect(downloads, 2, reason: 'two APKs on the first run, none after');
    });

    test('install failure throws AndroidBootstrapException(install)', () async {
      runner.onAdb(['install'],
          result: failed(stderr: 'Failure [INSTALL_FAILED]'));

      await expectLater(
        bootstrap().ensureServerReady(),
        throwsA(
          isA<AndroidBootstrapException>()
              .having(
                (e) => e.failure,
                'failure',
                AndroidBootstrapFailure.install,
              )
              .having(
                (e) => e.message,
                'message',
                contains('INSTALL_FAILED'),
              ),
        ),
      );
    });

    test('"already installed" is not treated as an install failure', () async {
      runner.onAdb(
        ['install'],
        result:
            failed(stderr: 'INSTALL_FAILED_ALREADY_EXISTS: already installed'),
      );

      await expectLater(bootstrap().ensureServerReady(), completes);
    });

    test('empty download throws download failure', () async {
      await expectLater(
        bootstrap(downloader: (_) async => <int>[]).ensureServerReady(),
        failsWith(AndroidBootstrapFailure.download),
      );
    });

    test(
      'detached: holds the instrumentation in a detached process',
      () async {
        final launches = <List<String>>[];
        final subject = AndroidBootstrap(
          serial: 'emulator-5554',
          processRunner: runner.call,
          processStarter: (_, __) =>
              throw StateError('a held process must not be started'),
          downloader: (_) async => [1],
          cacheDir: cacheDir,
          localPort: server.port,
          environment: const {},
          apkSha256: const {},
          isPortFree: (_) async => true,
          detached: true,
          detachedProcessStarter: (executable, arguments) async {
            launches.add([executable, ...arguments]);
            return _FakeProcess(4242);
          },
        );

        await subject.ensureServerReady();

        expect(launches.single.take(7), [
          'adb',
          '-s',
          'emulator-5554',
          'shell',
          'am',
          'instrument',
          '-w',
        ]);
        expect(subject.detachedPid, 4242);
        expect(
          runner.adbCommands.where((cmd) => cmd.contains('instrument')),
          isEmpty,
          reason: 'not started a second time without -w',
        );
      },
    );

    test('cachedApkValid: missing, mismatching and pinned copies', () async {
      const name = 'appium-uiautomator2-server-v10.3.2.apk';
      expect(await AndroidBootstrap.cachedApkValid(cacheDir, name), isNull);

      await File('${cacheDir.path}/$name').writeAsString('not an apk');
      expect(await AndroidBootstrap.cachedApkValid(cacheDir, name), isFalse);
    });

    test('stopServer force-stops both packages and removes the forward',
        () async {
      await AndroidBootstrap.stopServer(
        AdbClient(serial: 'emulator-5554', processRunner: runner.call),
        port: 8299,
      );

      expect(
        runner.adbCommands.where((cmd) => cmd.first != 'version'),
        [
          ['shell', 'am', 'force-stop', 'io.appium.uiautomator2.server.test'],
          ['shell', 'am', 'force-stop', 'io.appium.uiautomator2.server'],
          ['forward', '--remove', 'tcp:8299'],
        ],
      );
    });

    test('instrumentation start failure throws instrumentation', () async {
      runner.onAdb(
        ['shell', 'am', 'instrument'],
        result: failed(stderr: 'INSTRUMENTATION_FAILED'),
      );

      await expectLater(
        bootstrap().ensureServerReady(),
        failsWith(AndroidBootstrapFailure.instrumentation),
      );
    });

    test('port forward failure throws portForward', () async {
      runner.onAdb(['forward'], result: failed(stderr: 'cannot bind'));

      await expectLater(
        bootstrap().ensureServerReady(),
        failsWith(AndroidBootstrapFailure.portForward),
      );
    });

    test('failure tears down what was started', () async {
      runner.onAdb(['forward'], result: failed(stderr: 'cannot bind'));

      await expectLater(bootstrap().ensureServerReady(), throwsA(anything));

      expect(
        runner.adbCommands,
        contains(
          equals([
            'shell',
            'am',
            'force-stop',
            'io.appium.uiautomator2.server.test',
          ]),
        ),
      );
    });

    group('install', () {
      String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

      void deviceHasApks(String hash) {
        runner
          ..onAdb(
            ['shell', 'pm', 'path'],
            result: ok('package:/data/app/~~x/base.apk\n'),
          )
          ..onAdb(
            ['shell', 'sha256sum'],
            result: ok('$hash  /data/app/~~x/base.apk\n'),
          );
      }

      test('skips installing APKs identical to the ones on the device',
          () async {
        deviceHasApks(sha256Hex([1]));

        await bootstrap().ensureServerReady();

        expect(installs(), isEmpty);
      });

      test('installs when the device copy differs', () async {
        deviceHasApks(sha256Hex([9, 9]));

        await bootstrap().ensureServerReady();

        expect(installs(), hasLength(2));
      });

      test('installs when the device cannot report a checksum', () async {
        runner
            .onAdb(['shell', 'sha256sum'], result: failed(stderr: 'not found'));

        await bootstrap().ensureServerReady();

        expect(installs(), hasLength(2));
      });
    });

    group('APK checksums', () {
      Map<String, String> pinnedTo(List<int> bytes) => {
            for (final name in AndroidBootstrap.pinnedApkSha256.keys)
              name: sha256.convert(bytes).toString(),
          };

      test('rejects a download that does not match the pinned checksum',
          () async {
        await expectLater(
          bootstrap(
            downloader: (_) async => [6, 6, 6],
            apkSha256: pinnedTo([1]),
          ).ensureServerReady(),
          throwsA(
            isA<AndroidBootstrapException>()
                .having(
                  (e) => e.failure,
                  'failure',
                  AndroidBootstrapFailure.download,
                )
                .having((e) => e.message, 'message', contains('Checksum')),
          ),
        );
      });

      test('replaces a corrupted cached APK', () async {
        for (final name in AndroidBootstrap.pinnedApkSha256.keys) {
          await File('${cacheDir.path}/$name').writeAsBytes([0xBA, 0xD]);
        }
        var downloads = 0;

        await bootstrap(
          downloader: (_) async {
            downloads++;
            return [1];
          },
          apkSha256: pinnedTo([1]),
        ).ensureServerReady();

        expect(downloads, 2);
      });

      test('pins the checksums of the v${AndroidBootstrap.uia2Version} release',
          () {
        expect(AndroidBootstrap.pinnedApkSha256, hasLength(2));
        for (final hash in AndroidBootstrap.pinnedApkSha256.values) {
          expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
        }
      });
    });

    test('APK override pointing at a missing file fails clearly', () async {
      await expectLater(
        bootstrap(
          environment: {'MARIONETTE_UIA2_SERVER_APK': '/nope/server.apk'},
        ).ensureServerReady(),
        failsWith(AndroidBootstrapFailure.apkOverrideMissing),
      );
    });

    group('existing forward', () {
      void forwardTo(int port) => runner.on(
            'adb',
            ['forward', '--list'],
            result: ok('emulator-5554 tcp:$port tcp:6790\n'),
          );

      test('reuses a healthy server and leaves it running on dispose',
          () async {
        forwardTo(server.port);
        final subject = bootstrap(serial: 'emulator-5554', explicitPort: false);

        final uri = await subject.ensureServerReady();
        await subject.dispose();

        expect(uri.port, server.port);
        expect(subject.localPort, server.port);
        expect(installs(), isEmpty);
        expect(
          runner.adbCommands.where(
            (cmd) => cmd.contains('instrument') || cmd.contains('force-stop'),
          ),
          isEmpty,
        );
        expect(
          runner.adbCommands.where((cmd) => cmd.contains('--remove')),
          isEmpty,
        );
      });

      test('restarts the server on the forwarded port when it is unhealthy',
          () async {
        var statusCalls = 0;
        server.on('GET', '/status', (_) {
          statusCalls++;
          return statusCalls == 1
              ? const FakeResponse.raw('', status: HttpStatus.badGateway)
              : const FakeResponse.value({'ready': true});
        });
        forwardTo(server.port);
        final subject = bootstrap(serial: 'emulator-5554', explicitPort: false);

        final uri = await subject.ensureServerReady();

        expect(uri.port, server.port);
        expect(
          runner.adbCommands,
          contains(equals(['forward', 'tcp:${server.port}', 'tcp:6790'])),
        );
        expect(installs(), hasLength(2));
      });

      test('resolves the default device serial when none is given', () async {
        runner.onAdb(['get-serialno'], result: ok('emulator-5554\n'));
        forwardTo(server.port);

        final uri = await bootstrap(explicitPort: false).ensureServerReady();

        expect(uri.port, server.port);
        expect(installs(), isEmpty);
      });
    });
  });
}

void _portSelectionTests() {
  group('chooseUia2LocalPort', () {
    Future<bool> Function(int) freeExcept(Set<int> busy) =>
        (port) async => !busy.contains(port);

    test('an explicit port wins without probing', () async {
      expect(
        await chooseUia2LocalPort(
          explicitPort: 1234,
          environmentValue: '9999',
          isPortFree: (_) async => fail('must not probe'),
        ),
        1234,
      );
    });

    test('uses a free port from the environment', () async {
      expect(
        await chooseUia2LocalPort(
          explicitPort: null,
          environmentValue: ' 8300 ',
          isPortFree: freeExcept({}),
        ),
        8300,
      );
    });

    test('rejects a busy environment port with a hint', () async {
      await expectLater(
        chooseUia2LocalPort(
          explicitPort: null,
          environmentValue: '8300',
          isPortFree: freeExcept({8300}),
        ),
        throwsA(
          isA<AndroidBootstrapException>()
              .having(
                (e) => e.failure,
                'failure',
                AndroidBootstrapFailure.portForward,
              )
              .having((e) => e.hint, 'hint', contains('MARIONETTE_UIA2_PORT')),
        ),
      );
    });

    test('rejects an invalid environment value', () async {
      for (final raw in ['abc', '0', '70000']) {
        await expectLater(
          chooseUia2LocalPort(
            explicitPort: null,
            environmentValue: raw,
            isPortFree: freeExcept({}),
          ),
          throwsA(isA<AndroidBootstrapException>()),
          reason: raw,
        );
      }
    });

    test('otherwise picks the first free port from 8200', () async {
      expect(
        await chooseUia2LocalPort(
          explicitPort: null,
          environmentValue: null,
          isPortFree: freeExcept({8200, 8201}),
        ),
        8202,
      );
    });

    test('fails when the whole range is busy', () async {
      await expectLater(
        chooseUia2LocalPort(
          explicitPort: null,
          environmentValue: '',
          isPortFree: (_) async => false,
        ),
        throwsA(isA<AndroidBootstrapException>()),
      );
    });
  });
}

/// A started process of which only the pid is used.
class _FakeProcess implements Process {
  _FakeProcess(this.pid);

  @override
  final int pid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
