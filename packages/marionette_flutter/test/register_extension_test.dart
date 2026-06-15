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

    test('accepts a valid scalar-only schema', () {
      // Validation must not throw — the underlying VM service registration
      // will fail outside a real isolate, which is expected here.
      try {
        registerMarionetteExtension(
          name: 'reg.test.valid',
          description: 'A valid extension',
          inputSchema: const ExtensionInputSchema(
            properties: {
              'slideIndex': ExtensionParam.integer(minimum: 0),
              'animate': ExtensionParam.boolean(),
              'name': ExtensionParam.string(),
              'speed': ExtensionParam.number(),
            },
            required: ['slideIndex'],
          ),
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
      const schema = ExtensionInputSchema(
        properties: {
          'x': ExtensionParam.integer(),
        },
      );
      const details = ExtensionDetails(name: 'foo', inputSchema: schema);
      expect(details.inputSchema, same(schema));
    });

    test('inputSchema serializes to the expected wire format', () {
      const details = ExtensionDetails(
        name: 'appNavigation.goToPage',
        inputSchema: ExtensionInputSchema(
          properties: {
            'page': ExtensionParam.string(
              description: 'Page name.',
              enumValues: ['home', 'settings'],
            ),
          },
          required: ['page'],
        ),
      );

      expect(details.inputSchema!.toJson(), {
        'type': 'object',
        'properties': {
          'page': {
            'description': 'Page name.',
            'type': 'string',
            'enum': ['home', 'settings'],
          },
        },
        'required': ['page'],
      });
    });
  });
}
