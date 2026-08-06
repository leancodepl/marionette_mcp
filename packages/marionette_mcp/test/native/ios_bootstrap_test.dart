import 'dart:io';

import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:test/test.dart';

void main() {
  group('IosBootstrap', () {
    late Directory cacheDir;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('marionette_wda_');
    });

    tearDown(() async {
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    });

    test(
      'ensureServerReady throws on non-macOS',
      () async {
        final bootstrap = IosBootstrap(
          udid: 'TEST-UDID',
          processRunner: (executable, arguments) async => ProcessResult(0, 0, '', ''),
          cacheDir: cacheDir,
          wdaLocalPort: 18100,
          readyTimeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50),
        );

        expect(
          () => bootstrap.ensureServerReady(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('requires macOS'),
            ),
          ),
        );
      },
      skip: Platform.isMacOS ? 'requires a non-macOS host' : false,
    );

    test(
      'throws when no booted simulator is found',
      () async {
        final bootstrap = IosBootstrap(
          processRunner: (executable, arguments) async {
            expect(executable, 'xcrun');
            expect(arguments.take(3).toList(), ['simctl', 'list', 'devices']);
            return ProcessResult(
              0,
              0,
              '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-0": []}}',
              '',
            );
          },
          cacheDir: cacheDir,
          wdaLocalPort: 18101,
          readyTimeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50),
        );

        expect(
          () => bootstrap.ensureServerReady(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('No booted iOS Simulator'),
            ),
          ),
        );
      },
      skip: !Platform.isMacOS ? 'IosBootstrap requires macOS' : false,
    );

    test(
      'uses first booted simulator when multiple are booted',
      () async {
        const firstUdid = '11111111-1111-1111-1111-111111111111';
        final bootstrap = IosBootstrap(
          processRunner: (executable, arguments) async {
            expect(executable, 'xcrun');
            return ProcessResult(
              0,
              0,
              '''
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
      {"state": "Booted", "udid": "$firstUdid"},
      {"state": "Booted", "udid": "22222222-2222-2222-2222-222222222222"}
    ]
  }
}
''',
              '',
            );
          },
          cacheDir: cacheDir,
          wdaLocalPort: 18103,
        );

        try {
          await bootstrap.ensureServerReady();
          fail('expected missing WDA artifacts');
        } on StateError catch (e) {
          expect(e.message, contains('No prebuilt WebDriverAgent found'));
        }

        expect(bootstrap.resolvedUdid, firstUdid);
      },
      skip: !Platform.isMacOS ? 'IosBootstrap requires macOS' : false,
    );

    test(
      'throws a helpful message when WDA artifacts are missing',
      () async {
        final bootstrap = IosBootstrap(
          udid: 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
          processRunner: (executable, arguments) async => ProcessResult(0, 0, '', ''),
          cacheDir: cacheDir,
          wdaLocalPort: 18102,
          readyTimeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50),
        );

        expect(
          () => bootstrap.ensureServerReady(),
          throwsA(
            isA<StateError>()
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
      skip: !Platform.isMacOS ? 'IosBootstrap requires macOS' : false,
    );
  });
}
