import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  group('registerMarionetteExtension validation', () {
    test('throws when name is empty', () {
      expect(
        () => registerMarionetteExtension(
          name: '',
          callback: (_) async => MarionetteExtensionResult.success({}),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws when name has the ext.flutter. prefix', () {
      expect(
        () => registerMarionetteExtension(
          name: 'ext.flutter.bad',
          callback: (_) async => MarionetteExtensionResult.success({}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must not include the "ext.flutter." prefix'),
          ),
        ),
      );
    });

    test('throws when inputSchema top-level type is not "object"', () {
      expect(
        () => registerMarionetteExtension(
          name: 'broken',
          inputSchema: const {'type': 'string'},
          callback: (_) async => MarionetteExtensionResult.success({}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('top-level "type" must be "object"'),
          ),
        ),
      );
    });

    test('throws when inputSchema property type is not scalar', () {
      expect(
        () => registerMarionetteExtension(
          name: 'broken',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'tags': {'type': 'array'},
            },
          },
          callback: (_) async => MarionetteExtensionResult.success({}),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must declare a scalar "type"'),
          ),
        ),
      );
    });

    test('throws when inputSchema property is not a JSON object', () {
      expect(
        () => registerMarionetteExtension(
          name: 'broken',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'oops': 'not-a-schema',
            },
          },
          callback: (_) async => MarionetteExtensionResult.success({}),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts a valid scalar-only schema', () {
      // Validation must not throw — the underlying VM service registration
      // will fail outside a real isolate, which is expected here.
      try {
        registerMarionetteExtension(
          name: 'reg.test.valid',
          description: 'A valid extension',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'slideIndex': {'type': 'integer', 'minimum': 0},
              'animate': {'type': 'boolean'},
              'name': {'type': 'string'},
              'speed': {'type': 'number'},
            },
            'required': ['slideIndex'],
          },
          callback: (_) async => MarionetteExtensionResult.success({}),
        );
      } catch (e) {
        // The dart:developer registration may fail outside a VM service
        // context — that's downstream of the validation we care about.
        expect(e, isNot(isA<ArgumentError>()));
      }
    });
  });

  group('ExtensionDetails', () {
    test('inputSchema defaults to null', () {
      const details = ExtensionDetails(name: 'foo');
      expect(details.inputSchema, isNull);
    });

    test('preserves inputSchema verbatim', () {
      const schema = {
        'type': 'object',
        'properties': {
          'x': {'type': 'integer'},
        },
      };
      const details = ExtensionDetails(name: 'foo', inputSchema: schema);
      expect(details.inputSchema, same(schema));
    });
  });
}
