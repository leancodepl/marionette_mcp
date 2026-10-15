import 'dart:io';

import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';
import 'support/fake_webdriver_server.dart';

void main() {
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
    }) =>
        AndroidBootstrap(
          serial: serial,
          processRunner: runner.call,
          downloader: downloader ?? (_) async => [1],
          cacheDir: cacheDir,
          localPort: server.port,
        );

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
                  cmd.first == 'forward' ||
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

        // Serial is threaded into every adb invocation.
        expect(
          runner.calls.every(
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
  });
}
