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
      runner = FakeProcessRunner();
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
      'throws a helpful message when WDA artifacts are missing',
      () async {
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
          expect(runner.calls, isEmpty, reason: 'no launch needed');
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
