import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/extensions/device_config_extensions.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/services/device_config_service.dart';

/// Params reach an extension callback as `Map<String, String>` — the VM
/// stringifies every value on the way in — so these tests speak the wire
/// shape, not Dart types.
void main() {
  group('setDeviceConfig', () {
    late DeviceConfigService service;

    setUp(() {
      service = DeviceConfigService()..attach();
    });

    Map<String, Object?> successData(MarionetteExtensionResult result) {
      expect(result, isA<MarionetteExtensionSuccess>());
      return (result as MarionetteExtensionSuccess).data;
    }

    String invalidParamsDetail(MarionetteExtensionResult result) {
      expect(result, isA<MarionetteExtensionInvalidParams>());
      return (result as MarionetteExtensionInvalidParams).detail;
    }

    test('applies every field', () {
      final result = setDeviceConfig({
        'textScale': '1.5',
        'boldText': 'true',
        'platformBrightness': 'dark',
        'disableAnimations': 'true',
      }, service);

      expect(successData(result)['overrides'], {
        'textScale': 1.5,
        'boldText': true,
        'platformBrightness': 'dark',
        'disableAnimations': true,
      });
      expect(service.current.textScale, 1.5);
      expect(service.current.platformBrightness, Brightness.dark);
    });

    test('reports the applied overrides back to the caller', () {
      setDeviceConfig({'textScale': '2'}, service);
      final result = setDeviceConfig({'boldText': 'true'}, service);

      expect(successData(result)['overrides'], {
        'textScale': 2.0,
        'boldText': true,
      });
    });

    test('reset clears everything', () {
      setDeviceConfig({'textScale': '2', 'boldText': 'true'}, service);

      final result = setDeviceConfig({'reset': 'true'}, service);

      expect(successData(result)['message'], contains('reset'));
      expect(successData(result)['overrides'], isEmpty);
      expect(service.current.hasOverrides, isFalse);
    });

    test('reset with values applies exactly those values', () {
      // Not a silent no-op and not an error: reset clears first, then the
      // values in the same call are applied — which is also how a single
      // field is reverted.
      setDeviceConfig({'textScale': '2', 'boldText': 'true'}, service);

      final result = setDeviceConfig(
        {'reset': 'true', 'textScale': '3'},
        service,
      );

      expect(successData(result)['overrides'], {'textScale': 3.0});
    });

    test('rejects a call that sets nothing', () {
      final result = setDeviceConfig(const {}, service);

      expect(invalidParamsDetail(result), contains('At least one parameter'));
    });

    test('rejects reset=false with no other parameter', () {
      // Would otherwise report success having changed nothing.
      final result = setDeviceConfig({'reset': 'false'}, service);

      expect(invalidParamsDetail(result), contains('At least one parameter'));
    });

    test('reset=false alongside a value just sets the value', () {
      final result = setDeviceConfig(
        {'reset': 'false', 'textScale': '2'},
        service,
      );

      expect(successData(result)['overrides'], {'textScale': 2.0});
    });

    test('rejects a non-positive text scale', () {
      final result = setDeviceConfig({'textScale': '0'}, service);

      expect(invalidParamsDetail(result), contains('positive number'));
      expect(service.current.hasOverrides, isFalse);
    });

    test('rejects an unparseable text scale', () {
      final result = setDeviceConfig({'textScale': 'big'}, service);

      expect(invalidParamsDetail(result), contains('positive number'));
    });

    test('rejects a non-boolean boldText', () {
      final result = setDeviceConfig({'boldText': 'yes'}, service);

      expect(invalidParamsDetail(result), contains('"true" or "false"'));
    });

    test('rejects a non-boolean disableAnimations', () {
      final result = setDeviceConfig({'disableAnimations': '1'}, service);

      expect(invalidParamsDetail(result), contains('"true" or "false"'));
    });

    test('rejects an unknown brightness', () {
      final result = setDeviceConfig({'platformBrightness': 'sepia'}, service);

      expect(invalidParamsDetail(result), contains('"light" or "dark"'));
    });

    test('rejects a non-boolean reset', () {
      final result = setDeviceConfig({'reset': 'please'}, service);

      expect(invalidParamsDetail(result), contains('"true" or "false"'));
    });

    test('a rejected call leaves earlier overrides untouched', () {
      setDeviceConfig({'textScale': '2'}, service);

      setDeviceConfig({'textScale': '3', 'boldText': 'maybe'}, service);

      expect(service.current.textScale, 2);
    });

    test('returns setup instructions when no widget is mounted', () {
      final detached = DeviceConfigService();

      final result = setDeviceConfig({'textScale': '2'}, detached);

      expect(result, isA<MarionetteExtensionError>());
      final detail = (result as MarionetteExtensionError).detail;
      expect(detail, contains('MarionetteDeviceConfig'));
      expect(detail, contains('hot restart'));
      // Never suggest installing the binding unguarded — reaching this text
      // means it is already installed, and the guard belongs in the docs.
      expect(detail, isNot(contains('ensureInitialized')));
      expect(detached.current.hasOverrides, isFalse);
    });
  });
}
