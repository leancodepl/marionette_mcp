import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/device_config_service.dart';

void main() {
  group('DeviceConfigService', () {
    late DeviceConfigService service;

    setUp(() {
      service = DeviceConfigService();
    });

    test('initial overrides are empty', () {
      expect(service.current.hasOverrides, isFalse);
      expect(service.current.textScaleFactor, isNull);
      expect(service.current.boldText, isNull);
    });

    test('setOverrides applies textScaleFactor', () {
      final result = service.setOverrides(textScaleFactor: 2.0);
      expect(result.textScaleFactor, equals(2.0));
      expect(result.boldText, isNull);
    });

    test('setOverrides applies boldText', () {
      final result = service.setOverrides(boldText: true);
      expect(result.textScaleFactor, isNull);
      expect(result.boldText, isTrue);
    });

    test('setOverrides merges with existing values', () {
      service.setOverrides(textScaleFactor: 1.5);
      final result = service.setOverrides(boldText: true);
      expect(result.textScaleFactor, equals(1.5));
      expect(result.boldText, isTrue);
    });

    test('resetTextScaleFactor clears only textScaleFactor', () {
      service.setOverrides(textScaleFactor: 2.0, boldText: true);
      final result = service.setOverrides(resetTextScaleFactor: true);
      expect(result.textScaleFactor, isNull);
      expect(result.boldText, isTrue);
    });

    test('resetBoldText clears only boldText', () {
      service.setOverrides(textScaleFactor: 2.0, boldText: true);
      final result = service.setOverrides(resetBoldText: true);
      expect(result.textScaleFactor, equals(2.0));
      expect(result.boldText, isNull);
    });

    test('toJson only includes non-null fields', () {
      expect(const DeviceConfigOverrides().toJson(), isEmpty);
      expect(
        const DeviceConfigOverrides(textScaleFactor: 1.5).toJson(),
        equals({'textScaleFactor': 1.5}),
      );
      expect(
        const DeviceConfigOverrides(boldText: true).toJson(),
        equals({'boldText': true}),
      );
    });
  });

  group('DeviceConfigWrapper', () {
    testWidgets(
      'passes through child when no overrides are set',
      (WidgetTester tester) async {
        final overrides = ValueNotifier(const DeviceConfigOverrides());

        await tester.pumpWidget(
          MaterialApp(
            home: DeviceConfigWrapper(
              overrides: overrides,
              child: Builder(
                builder: (context) {
                  return Text(
                    'scale: ${MediaQuery.textScalerOf(context).scale(1.0)}',
                  );
                },
              ),
            ),
          ),
        );

        // Default text scale factor is 1.0
        expect(find.text('scale: 1.0'), findsOneWidget);
      },
    );

    testWidgets(
      'applies textScaleFactor override',
      (WidgetTester tester) async {
        final overrides =
            ValueNotifier(const DeviceConfigOverrides(textScaleFactor: 2.0));

        await tester.pumpWidget(
          MaterialApp(
            home: DeviceConfigWrapper(
              overrides: overrides,
              child: Builder(
                builder: (context) {
                  return Text(
                    'scale: ${MediaQuery.textScalerOf(context).scale(1.0)}',
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('scale: 2.0'), findsOneWidget);
      },
    );

    testWidgets(
      'applies boldText override',
      (WidgetTester tester) async {
        final overrides =
            ValueNotifier(const DeviceConfigOverrides(boldText: true));

        await tester.pumpWidget(
          MaterialApp(
            home: DeviceConfigWrapper(
              overrides: overrides,
              child: Builder(
                builder: (context) {
                  final bold = MediaQuery.boldTextOf(context);
                  return Text('bold: $bold');
                },
              ),
            ),
          ),
        );

        expect(find.text('bold: true'), findsOneWidget);
      },
    );

    testWidgets(
      'rebuilds when overrides change',
      (WidgetTester tester) async {
        final overrides = ValueNotifier(const DeviceConfigOverrides());

        await tester.pumpWidget(
          MaterialApp(
            home: DeviceConfigWrapper(
              overrides: overrides,
              child: Builder(
                builder: (context) {
                  return Text(
                    'scale: ${MediaQuery.textScalerOf(context).scale(1.0)}',
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('scale: 1.0'), findsOneWidget);

        overrides.value = const DeviceConfigOverrides(textScaleFactor: 3.0);
        await tester.pump();

        expect(find.text('scale: 3.0'), findsOneWidget);
      },
    );
  });
}
