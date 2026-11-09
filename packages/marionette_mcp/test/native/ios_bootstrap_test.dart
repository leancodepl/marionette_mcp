import 'dart:io';

import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:test/test.dart';

import 'support/fake_process_runner.dart';
import 'support/fake_webdriver_server.dart';

const _macOnly = 'IosBootstrap requires macOS';

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

    IosBootstrap bootstrap({String? udid, int port = 18100, String? wdaPath}) =>
        IosBootstrap(
          udid: udid,
          processRunner: runner.call,
          cacheDir: cacheDir,
          wdaLocalPort: port,
          wdaPath: wdaPath,
          readyTimeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50),
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

    test(
      'ensureServerReady throws notMacOS on non-macOS',
      () async {
        await expectLater(
          bootstrap(udid: 'TEST-UDID').ensureServerReady(),
          failsWith(IosBootstrapFailure.notMacOS, 'requires macOS'),
        );
      },
      skip: Platform.isMacOS ? 'requires a non-macOS host' : false,
    );

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
      skip: !Platform.isMacOS ? _macOnly : false,
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
      skip: !Platform.isMacOS ? _macOnly : false,
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
      skip: !Platform.isMacOS ? _macOnly : false,
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
      skip: !Platform.isMacOS ? _macOnly : false,
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
      skip: !Platform.isMacOS ? _macOnly : false,
    );

    group('with WDA already listening', () {
      late FakeWebDriverServer wda;

      setUp(() async {
        wda = await FakeWebDriverServer.start();
        wda.onValue('GET', '/wda/device/info', {'udid': 'SIM-A'});
      });

      tearDown(() => wda.close());

      test(
        'reuses a healthy WDA serving the same simulator',
        () async {
          final uri = await bootstrap(udid: 'SIM-A', port: wda.port)
              .ensureServerReady();

          expect(uri.port, wda.port);
          expect(
            runner.calls.map((c) => c.arguments.take(2).join(' ')),
            everyElement('simctl list'),
            reason: 'no launch needed',
          );
        },
        skip: !Platform.isMacOS ? _macOnly : false,
      );

      test(
        'without a reported udid, reuses WDA whose runner runs in the '
        'simulator (WDA 16)',
        () async {
          wda.onValue('GET', '/wda/device/info', {'uuid': 'APP-VENDOR-ID'});
          runner
            ..on(
              'xcrun',
              ['simctl', 'spawn', 'SIM-A', 'launchctl', 'list'],
              result: ok(
                '43645\t0\tUIKitApplication:'
                'com.facebook.WebDriverAgentRunner.xctrunner[a55b][rb-legacy]\n',
              ),
            )
            ..on(
              'xcrun',
              ['simctl', 'spawn', 'SIM-B', 'launchctl', 'list'],
              result: ok('-\t0\tcom.apple.Preferences\n'),
            );

          final uri = await bootstrap(udid: 'SIM-A', port: wda.port)
              .ensureServerReady();
          expect(uri.port, wda.port);
          await expectLater(
            bootstrap(udid: 'SIM-B', port: wda.port).ensureServerReady(),
            failsWith(IosBootstrapFailure.portConflict, 'SIM-B'),
          );
        },
        skip: !Platform.isMacOS ? _macOnly : false,
      );

      test(
        'throws portConflict when WDA on the port serves another simulator',
        () async {
          await expectLater(
            bootstrap(udid: 'SIM-B', port: wda.port).ensureServerReady(),
            failsWith(IosBootstrapFailure.portConflict, 'SIM-B'),
          );
        },
        skip: !Platform.isMacOS ? _macOnly : false,
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
          ).ensureServerReady(),
          throwsA(
            isA<IosBootstrapException>()
                .having((e) => e.failure, 'failure',
                    IosBootstrapFailure.portConflict)
                .having((e) => e.hint, 'hint', contains('lsof')),
          ),
        );
      },
      skip: !Platform.isMacOS ? _macOnly : false,
    );

    test(
      'detached: starts xcodebuild detached and reports its pid',
      () async {
        final wda = await FakeWebDriverServer.start();
        addTearDown(wda.close);
        var started = false;
        // Healthy only once xcodebuild has been started.
        wda.on(
          'GET',
          '/status',
          (_) => started
              ? const FakeResponse.value({'ready': true})
              : const FakeResponse.error('unknown error', 'starting'),
        );
        await File('${cacheDir.path}/WDA.xctestrun').create();
        final launches = <List<String>>[];

        final subject = IosBootstrap(
          udid: 'SIM-A',
          processRunner: runner.call,
          processStarter: (_, __) =>
              throw StateError('a held process must not be started'),
          cacheDir: cacheDir,
          wdaLocalPort: wda.port,
          readyTimeout: const Duration(seconds: 2),
          pollInterval: const Duration(milliseconds: 50),
          // The fake WDA listens before it is "started".
          isPortFree: (_) async => true,
          detached: true,
          detachedProcessStarter: (executable, arguments) async {
            launches.add([executable, ...arguments]);
            started = true;
            return _FakeProcess(4242);
          },
        );

        final uri = await subject.ensureServerReady();

        expect(uri.port, wda.port);
        expect(
            launches.single.take(2), ['xcodebuild', 'test-without-building']);
        expect(subject.detachedPid, 4242);
      },
      skip: !Platform.isMacOS ? _macOnly : false,
    );

    test(
      'simctl launch failure throws launch with the XCTest hint',
      () async {
        final app = await Directory(
          '${cacheDir.path}/WebDriverAgentRunner-Runner.app',
        ).create();
        runner.on(
          'xcrun',
          ['simctl', 'install'],
          result: failed(stderr: 'Invalid bundle'),
        );

        await expectLater(
          bootstrap(udid: 'SIM-A', port: 18104, wdaPath: app.path)
              .ensureServerReady(),
          throwsA(
            isA<IosBootstrapException>()
                .having((e) => e.failure, 'failure', IosBootstrapFailure.launch)
                .having((e) => e.message, 'message', contains('Invalid bundle'))
                .having(
                  (e) => e.hint,
                  'hint',
                  contains('MARIONETTE_WDA_XCTESTRUN'),
                ),
          ),
        );
      },
      skip: !Platform.isMacOS ? _macOnly : false,
    );
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
