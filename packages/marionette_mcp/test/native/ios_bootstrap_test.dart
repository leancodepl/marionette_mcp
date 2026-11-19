import 'dart:io';

import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:test/test.dart';

import 'support/fake_process.dart';
import 'support/fake_process_runner.dart';
import 'support/fake_webdriver_server.dart';

String _bootedJson(List<String> udids) => '''
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
      ${udids.map((udid) => '{"state": "Booted", "udid": "$udid"}').join(',\n')}
    ]
  }
}
''';

void main() {
  group('IosBootstrap', () {
    late Directory cacheDir;
    late FakeProcessRunner runner;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('marionette_wda_');
      // Default: the simulators named by the tests are booted. Tests that
      // need another listing register their own (the latest rule wins).
      runner = FakeProcessRunner()
        ..on(
          'xcrun',
          ['simctl', 'list'],
          result: ok(_bootedJson(['SIM-A', 'SIM-B'])),
        );
    });

    tearDown(() async {
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    });

    IosBootstrap bootstrap({
      String? udid,
      int port = 18100,
      String? wdaPath,
      String operatingSystem = 'macos',
    }) =>
        IosBootstrap(
          udid: udid,
          processRunner: runner.call,
          cacheDir: cacheDir,
          wdaLocalPort: port,
          wdaPath: wdaPath,
          readyTimeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50),
          operatingSystem: operatingSystem,
        );

    Matcher failsWith(IosBootstrapFailure failure, [String? messagePart]) {
      var matcher = isA<IosBootstrapException>()
          .having((e) => e.failure, 'failure', failure);
      if (messagePart != null) {
        matcher =
            matcher.having((e) => e.message, 'message', contains(messagePart));
      }
      return throwsA(matcher);
    }

    /// An [IosBootstrap] for `SIM-A` whose WDA turns healthy once
    /// [startXcodebuild] has started it, [detached] or held; never when not
    /// [ready].
    Future<IosBootstrap> bootstrapStartingWda(
      ProcessStarter startXcodebuild, {
      bool detached = false,
      bool ready = true,
    }) async {
      final wda = await FakeWebDriverServer.start();
      addTearDown(wda.close);
      var started = false;
      wda.on(
        'GET',
        '/status',
        (_) => started && ready
            ? const FakeResponse.value({'ready': true})
            : const FakeResponse.error('unknown error', 'starting'),
      );
      await File('${cacheDir.path}/WDA.xctestrun').create();
      Future<Process> start(String executable, List<String> arguments) {
        started = true;
        return startXcodebuild(executable, arguments);
      }

      Future<Process> mustNotStart(String _, List<String> __) =>
          throw StateError('xcodebuild must not start in this mode');

      return IosBootstrap(
        udid: 'SIM-A',
        processRunner: runner.call,
        processStarter: detached ? mustNotStart : start,
        detachedProcessStarter: detached ? start : mustNotStart,
        cacheDir: cacheDir,
        wdaLocalPort: wda.port,
        readyTimeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 50),
        // The fake WDA listens before xcodebuild is started.
        isPortFree: (_) async => true,
        detached: detached,
        operatingSystem: 'macos',
      );
    }

    test(
        'ensureServerReady throws notMacOS on a Linux host without running '
        'a process', () async {
      await expectLater(
        bootstrap(udid: 'TEST-UDID', operatingSystem: 'linux')
            .ensureServerReady(),
        failsWith(IosBootstrapFailure.notMacOS, 'requires macOS'),
      );
      expect(runner.calls, isEmpty);
    });

    test(
      'throws noBootedSimulator when no simulator is booted',
      () async {
        runner.on(
          'xcrun',
          ['simctl', 'list', 'devices'],
          result: ok(_bootedJson([])),
        );

        await expectLater(
          bootstrap().ensureServerReady(),
          failsWith(IosBootstrapFailure.noBootedSimulator),
        );
      },
    );

    test(
      'throws simctl failure when listing simulators fails',
      () async {
        runner.on(
          'xcrun',
          ['simctl', 'list'],
          result: failed(stderr: 'CoreSimulator is out of date'),
        );

        await expectLater(
          bootstrap().ensureServerReady(),
          failsWith(IosBootstrapFailure.simctl, 'CoreSimulator'),
        );
      },
    );

    test(
      'uses first booted simulator when multiple are booted',
      () async {
        const firstUdid = '11111111-1111-1111-1111-111111111111';
        runner.on(
          'xcrun',
          ['simctl', 'list'],
          result: ok(
            _bootedJson([firstUdid, '22222222-2222-2222-2222-222222222222']),
          ),
        );
        final subject = bootstrap(port: 18103);

        await expectLater(
          subject.ensureServerReady(),
          failsWith(IosBootstrapFailure.wdaArtifactsMissing),
        );
        expect(subject.resolvedUdid, firstUdid);
      },
    );

    test(
      'throws noBootedSimulator for an explicit udid that is not booted',
      () async {
        runner.on(
          'xcrun',
          ['simctl', 'list'],
          result: ok(_bootedJson(['OTHER-UDID'])),
        );

        await expectLater(
          bootstrap(udid: 'SHUTDOWN-UDID').ensureServerReady(),
          throwsA(
            isA<IosBootstrapException>()
                .having(
                  (e) => e.failure,
                  'failure',
                  IosBootstrapFailure.noBootedSimulator,
                )
                .having((e) => e.message, 'message', contains('SHUTDOWN-UDID'))
                .having((e) => e.message, 'message', contains('OTHER-UDID'))
                .having((e) => e.hint, 'hint', contains('simctl boot')),
          ),
        );
      },
    );

    test(
      'throws a helpful message when WDA artifacts are missing',
      () async {
        runner.on(
          'xcrun',
          ['simctl', 'list'],
          result: ok(_bootedJson(['AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'])),
        );
        await expectLater(
          bootstrap(udid: 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE', port: 18102)
              .ensureServerReady(),
          throwsA(
            isA<IosBootstrapException>()
                .having(
                  (e) => e.failure,
                  'failure',
                  IosBootstrapFailure.wdaArtifactsMissing,
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('No prebuilt WebDriverAgent found'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('MARIONETTE_WDA_XCTESTRUN'),
                ),
          ),
        );
      },
    );

    group('with WDA already listening', () {
      late FakeWebDriverServer wda;

      setUp(() async {
        wda = await FakeWebDriverServer.start();
      });

      tearDown(() => wda.close());

      test('reuses WDA whose runner runs in the simulator', () async {
        runner.on(
          'xcrun',
          ['simctl', 'spawn', 'SIM-A', 'launchctl', 'list'],
          result: ok(
            '43645\t0\tUIKitApplication:'
            'com.facebook.WebDriverAgentRunner.xctrunner[a55b][rb-legacy]\n',
          ),
        );

        final uri =
            await bootstrap(udid: 'SIM-A', port: wda.port).ensureServerReady();
        expect(uri.port, wda.port);
      });

      test(
          'a failed launchctl fails at simctl with its error, not as a '
          'port conflict', () async {
        runner.on(
          'xcrun',
          ['simctl', 'spawn', 'SIM-A', 'launchctl', 'list'],
          result: failed(stderr: 'launchctl: no such process'),
        );

        await expectLater(
          bootstrap(udid: 'SIM-A', port: wda.port).ensureServerReady(),
          failsWith(IosBootstrapFailure.simctl, 'no such process'),
        );
      });

      test('an xcrun that cannot be run fails at simctl', () async {
        runner.on(
          'xcrun',
          ['simctl', 'spawn'],
          error: const ProcessException('xcrun', [], 'Permission denied'),
        );

        await expectLater(
          bootstrap(udid: 'SIM-A', port: wda.port).ensureServerReady(),
          failsWith(IosBootstrapFailure.simctl, 'Permission denied'),
        );
      });

      test(
        'throws portConflict naming the one-simulator limit when WDA on the '
        'port serves another simulator',
        () async {
          await expectLater(
            bootstrap(udid: 'SIM-B', port: wda.port).ensureServerReady(),
            failsWith(
              IosBootstrapFailure.portConflict,
              'one iOS Simulator at a time',
            ),
          );
        },
      );
    });

    test(
      'a port taken by another program fails fast with portConflict',
      () async {
        await File('${cacheDir.path}/WDA.xctestrun').create();

        await expectLater(
          IosBootstrap(
            udid: 'SIM-A',
            processRunner: runner.call,
            processStarter: (_, __) => throw StateError('must not launch'),
            cacheDir: cacheDir,
            wdaLocalPort: 18199,
            isPortFree: (_) async => false,
            operatingSystem: 'macos',
          ).ensureServerReady(),
          throwsA(
            isA<IosBootstrapException>()
                .having((e) => e.failure, 'failure',
                    IosBootstrapFailure.portConflict)
                .having((e) => e.hint, 'hint', contains('lsof')),
          ),
        );
      },
    );

    test('an xcodebuild that exits before WDA is ready fails at launch',
        () async {
      final subject = await bootstrapStartingWda(
        (_, __) async => FakeProcess()..exit(65),
        ready: false,
      );

      await expectLater(
        subject.ensureServerReady(),
        failsWith(IosBootstrapFailure.launch, 'code 65'),
      );
    });

    test(
      'detached: starts xcodebuild detached and reports its pid',
      () async {
        const pid = (1 << 30) + 1;
        final launches = <List<String>>[];
        final subject = await bootstrapStartingWda(
          (executable, arguments) async {
            launches.add([executable, ...arguments]);
            return FakeProcess(pid: pid);
          },
          detached: true,
        );

        final uri = await subject.ensureServerReady();

        expect(uri.port, subject.wdaLocalPort);
        expect(
            launches.single.take(2), ['xcodebuild', 'test-without-building']);
        expect(subject.detachedPid, pid);
      },
    );

    test('dispose stops listening to the xcodebuild output', () async {
      final xcodebuild = FakeProcess();
      final subject = await bootstrapStartingWda((_, __) async => xcodebuild);
      await subject.ensureServerReady();

      await subject.dispose();

      expect(xcodebuild.stdoutController.hasListener, isFalse);
      expect(xcodebuild.stderrController.hasListener, isFalse);
    });

    test(
      'a runner .app without an .xctestrun fails with wdaArtifactsMissing',
      () async {
        await Directory(
          '${cacheDir.path}/WebDriverAgentRunner-Runner.app',
        ).create();

        await expectLater(
          bootstrap(udid: 'SIM-A', port: 18104).ensureServerReady(),
          failsWith(IosBootstrapFailure.wdaArtifactsMissing),
        );
        expect(
          runner.calls.map((c) => c.arguments.take(2).join(' ')),
          everyElement('simctl list'),
          reason: 'no simctl install or launch',
        );
      },
    );
  });
}
