import 'dart:async';

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
      'brightness=${data.platformBrightness.name}',
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
          'scale=10.0 bold=false brightness=light',
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
      );
      await tester.pump();

      expect(
        _probeText('scale=15.0 bold=true brightness=dark'),
        findsOneWidget,
      );
    });

    testWidgets('propagates through MaterialApp to the app below', (
      tester,
    ) async {
      // MaterialApp inserts no MediaQuery of its own — View installs the only
      // one, above us — so an override placed here is what the app resolves,
      // theme included.
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

    testWidgets('keeps the app alive across an override and a reset', (
      tester,
    ) async {
      // The wrapper must not change the shape of the tree below it when an
      // override arrives: Flutter rebuilds a subtree from scratch when the
      // widget at a position changes type, which would drop the State of
      // every widget in the app mid-session.
      final service = DeviceConfigService();
      _StatefulProbe.mounts = 0;

      await tester.pumpWidget(
        MarionetteDeviceConfig(service: service, child: const _StatefulProbe()),
      );
      tester.state<_StatefulProbeState>(find.byType(_StatefulProbe)).value = 7;
      expect(_StatefulProbe.mounts, 1);

      service.setOverrides(textScale: 2);
      await tester.pump();

      expect(_StatefulProbe.mounts, 1, reason: 'override must not remount');
      expect(
        tester.state<_StatefulProbeState>(find.byType(_StatefulProbe)).value,
        7,
      );
      expect(_probeText('scale=20.0'), findsOneWidget);

      service.setOverrides(reset: true);
      await tester.pump();

      expect(_StatefulProbe.mounts, 1, reason: 'reset must not remount');
      expect(
        tester.state<_StatefulProbeState>(find.byType(_StatefulProbe)).value,
        7,
      );
      expect(_probeText('scale=10.0'), findsOneWidget);
    });

    testWidgets('keeps a pushed route alive when an override is applied', (
      tester,
    ) async {
      final service = DeviceConfigService();
      late BuildContext homeContext;
      _StatefulProbe.mounts = 0;

      await tester.pumpWidget(
        MarionetteDeviceConfig(
          service: service,
          // No navigatorKey: a GlobalKey lets Flutter reparent the Navigator
          // and would hide a rebuild of the subtree. Most apps don't have one.
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                homeContext = context;
                return const Scaffold(body: Text('home'));
              },
            ),
          ),
        ),
      );

      // Not awaited: push() completes when the route is popped.
      unawaited(
        Navigator.of(homeContext).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: _StatefulProbe()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_StatefulProbe.mounts, 1);
      tester.state<_StatefulProbeState>(find.byType(_StatefulProbe)).value = 7;

      service.setOverrides(textScale: 2);
      await tester.pumpAndSettle();

      expect(
        _StatefulProbe.mounts,
        1,
        reason: 'the pushed route must survive the override',
      );
      expect(
        tester.state<_StatefulProbeState>(find.byType(_StatefulProbe)).value,
        7,
      );
      expect(_probeText('scale=20.0'), findsOneWidget);
    });

    testWidgets('follows platform changes while an override is set', (
      tester,
    ) async {
      // The injected MediaQuery must not freeze the platform fields it does
      // not override — it copies from the live ancestor View.MediaQuery, so a
      // platform brightness change still reaches the app.
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final service = DeviceConfigService()..setOverrides(textScale: 2);

      await tester.pumpWidget(
        MarionetteDeviceConfig(service: service, child: const _Probe()),
      );
      expect(
          _probeText('scale=20.0 bold=false brightness=light'), findsOneWidget);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();

      expect(
        _probeText('scale=20.0 bold=false brightness=dark'),
        findsOneWidget,
      );
    });
  });
}

/// A [_Probe] that also reports how often it has been mounted, so a test can
/// tell a rebuild from a teardown-and-rebuild.
class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe();

  static int mounts = 0;

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  /// Stands in for whatever state a real app holds — form contents, scroll
  /// offsets, a half-finished flow.
  int value = 0;

  @override
  void initState() {
    super.initState();
    _StatefulProbe.mounts++;
  }

  @override
  Widget build(BuildContext context) => const _Probe();
}
