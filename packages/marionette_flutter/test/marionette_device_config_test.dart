import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/device_config_service.dart';
import 'package:marionette_flutter/src/widgets/marionette_device_config.dart';

/// Reads the [MediaQuery] values an app below the wrapper would see.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    return Text(
      'scale=${data.textScaler.scale(10)} '
      'bold=${data.boldText} '
      'brightness=${data.platformBrightness.name} '
      'animations=${data.disableAnimations}',
      textDirection: TextDirection.ltr,
    );
  }
}

Finder _probeText(String contents) => find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data ?? '').contains(contents),
    );

void main() {
  group('MarionetteDeviceConfig', () {
    testWidgets('attaches on mount and detaches on dispose', (tester) async {
      final service = DeviceConfigService();

      await tester.pumpWidget(
        MarionetteDeviceConfig(service: service, child: const _Probe()),
      );
      expect(service.isAttached, isTrue);

      await tester.pumpWidget(const _Probe());

      expect(service.isAttached, isFalse);
    });

    testWidgets('drops overrides when unmounted, so a remount starts clean', (
      tester,
    ) async {
      final service = DeviceConfigService();

      Widget tree({required bool mounted}) => mounted
          ? MarionetteDeviceConfig(service: service, child: const _Probe())
          : const _Probe();

      await tester.pumpWidget(tree(mounted: true));
      service.setOverrides(textScale: 2);
      await tester.pump();
      expect(_probeText('scale=20.0'), findsOneWidget);

      await tester.pumpWidget(tree(mounted: false));
      await tester.pumpWidget(tree(mounted: true));

      expect(service.isAttached, isTrue);
      expect(_probeText('scale=10.0'), findsOneWidget);
    });

    testWidgets('leaves MediaQuery untouched while no override is set', (
      tester,
    ) async {
      final service = DeviceConfigService();

      await tester.pumpWidget(
        MarionetteDeviceConfig(service: service, child: const _Probe()),
      );

      expect(
        _probeText(
          'scale=10.0 bold=false brightness=light animations=false',
        ),
        findsOneWidget,
      );
    });

    testWidgets('applies every override and rebuilds on change', (
      tester,
    ) async {
      final service = DeviceConfigService();

      await tester.pumpWidget(
        MarionetteDeviceConfig(service: service, child: const _Probe()),
      );

      service.setOverrides(
        textScale: 1.5,
        boldText: true,
        platformBrightness: Brightness.dark,
        disableAnimations: true,
      );
      await tester.pump();

      expect(
        _probeText('scale=15.0 bold=true brightness=dark animations=true'),
        findsOneWidget,
      );
    });

    testWidgets('propagates through MaterialApp to the app below', (
      tester,
    ) async {
      // MaterialApp inserts its own MediaQuery.fromView, which takes the
      // platform fields from the nearest ancestor MediaQuery — ours. Without
      // that, an override above MaterialApp would never reach the app.
      final service = DeviceConfigService()
        ..setOverrides(textScale: 2, platformBrightness: Brightness.dark);

      await tester.pumpWidget(
        MarionetteDeviceConfig(
          service: service,
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            home: const _Probe(),
          ),
        ),
      );

      expect(_probeText('scale=20.0'), findsOneWidget);
      expect(_probeText('brightness=dark'), findsOneWidget);
      expect(
        Theme.of(tester.element(_probeText('scale=20.0'))).brightness,
        Brightness.dark,
      );
    });

    testWidgets('is a pass-through when no binding was installed', (
      tester,
    ) async {
      // `service` defaults to MarionetteBinding.maybeDeviceConfigService,
      // which is null under the plain test binding — a release build behaves
      // the same way.
      await tester.pumpWidget(const MarionetteDeviceConfig(child: _Probe()));

      expect(
        find.byType(ValueListenableBuilder<DeviceConfigOverrides>),
        findsNothing,
      );
      expect(_probeText('scale=10.0'), findsOneWidget);
    });

    testWidgets('moves attachment when the service is swapped', (
      tester,
    ) async {
      final first = DeviceConfigService();
      final second = DeviceConfigService();

      await tester.pumpWidget(
        MarionetteDeviceConfig(service: first, child: const _Probe()),
      );
      await tester.pumpWidget(
        MarionetteDeviceConfig(service: second, child: const _Probe()),
      );

      expect(first.isAttached, isFalse);
      expect(second.isAttached, isTrue);
    });
  });
}
