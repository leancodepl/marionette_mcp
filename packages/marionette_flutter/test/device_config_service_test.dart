import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/device_config_service.dart';

void main() {
  group('DeviceConfigService', () {
    late DeviceConfigService service;

    setUp(() {
      service = DeviceConfigService();
    });

    test('starts with no overrides', () {
      expect(service.current.hasOverrides, isFalse);
      expect(service.current.toJson(), isEmpty);
    });

    test('merges successive calls instead of replacing', () {
      service.setOverrides(textScale: 2);
      final result = service.setOverrides(boldText: true);

      expect(result.textScale, 2);
      expect(result.boldText, isTrue);
      expect(service.current, result);
    });

    test('reset drops every override', () {
      service.setOverrides(
        textScale: 2,
        boldText: true,
        platformBrightness: Brightness.dark,
      );

      final result = service.setOverrides(reset: true);

      expect(result.hasOverrides, isFalse);
    });

    test('reset combined with values keeps only those values', () {
      service.setOverrides(textScale: 2, boldText: true);

      final result = service.setOverrides(reset: true, textScale: 3);

      expect(result.textScale, 3);
      expect(result.boldText, isNull);
    });

    test('notifies listeners on change', () {
      final seen = <DeviceConfigOverrides>[];
      service.overrides.addListener(() => seen.add(service.current));

      service
        ..setOverrides(textScale: 2)
        ..setOverrides(reset: true);

      expect(seen, hasLength(2));
      expect(seen.first.textScale, 2);
      expect(seen.last.hasOverrides, isFalse);
    });

    test('serializes only the fields that are overridden', () {
      service.setOverrides(
        textScale: 1.5,
        platformBrightness: Brightness.dark,
      );

      expect(service.current.toJson(), {
        'textScale': 1.5,
        'platformBrightness': 'dark',
      });
    });

    group('attachment', () {
      test('is not attached until a widget attaches', () {
        expect(service.isAttached, isFalse);

        service.attach();

        expect(service.isAttached, isTrue);
      });

      test('stays attached while any widget is still mounted', () {
        service
          ..attach()
          ..attach()
          ..detach();

        expect(service.isAttached, isTrue);
      });

      test('drops overrides when the last widget detaches', () {
        service
          ..attach()
          ..setOverrides(textScale: 2)
          ..detach();

        expect(service.isAttached, isFalse);
        expect(service.current.hasOverrides, isFalse);
      });

      test('an unbalanced detach cannot drive the count negative', () {
        service
          ..detach()
          ..attach();

        expect(service.isAttached, isTrue);
      });
    });
  });
}
