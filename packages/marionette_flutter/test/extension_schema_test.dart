import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  group('ExtensionInputSchema.toJson', () {
    test('emits an empty object schema by default', () {
      const schema = ExtensionInputSchema();
      expect(schema.toJson(), {
        'type': 'object',
        'properties': <String, dynamic>{},
      });
    });

    test('omits "required" when no properties are required', () {
      const schema = ExtensionInputSchema(
        properties: {'name': ExtensionParam.string()},
      );
      expect(schema.toJson(), {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      });
    });

    test('emits "required" when set', () {
      const schema = ExtensionInputSchema(
        properties: {'name': ExtensionParam.string()},
        required: ['name'],
      );
      expect(schema.toJson()['required'], ['name']);
    });

    test('emits title and description when set', () {
      const schema = ExtensionInputSchema(
        title: 'Navigate',
        description: 'Navigates to a named page.',
      );
      final json = schema.toJson();
      expect(json['title'], 'Navigate');
      expect(json['description'], 'Navigates to a named page.');
    });
  });

  group('ExtensionParam.string', () {
    test('emits "type": "string" with no other fields by default', () {
      expect(const ExtensionParam.string().toJson(), {'type': 'string'});
    });

    test('emits all set metadata using JSON Schema field names', () {
      const param = ExtensionParam.string(
        title: 'Name',
        description: 'A name.',
        defaultValue: 'anon',
        minLength: 1,
        maxLength: 64,
        pattern: r'^[a-z]+$',
        format: 'email',
        enumValues: ['a', 'b'],
      );
      expect(param.toJson(), {
        'title': 'Name',
        'description': 'A name.',
        'default': 'anon',
        'type': 'string',
        'minLength': 1,
        'maxLength': 64,
        'pattern': r'^[a-z]+$',
        'format': 'email',
        'enum': ['a', 'b'],
      });
    });

    test('serializes a runtime-built enum list', () {
      // Mirrors the example app's pattern: enumValues comes from
      // availablePages.keys.toList() rather than a const literal.
      final values = ['home', 'profile', 'settings'];
      final param = ExtensionParam.string(enumValues: values);
      final json = param.toJson();
      expect(json['enum'], ['home', 'profile', 'settings']);
      // The list should be a copy — mutating the source must not affect
      // already-serialized JSON.
      values.add('extra');
      expect(json['enum'], ['home', 'profile', 'settings']);
    });
  });

  group('ExtensionParam.integer', () {
    test('emits "type": "integer" with no other fields by default', () {
      expect(const ExtensionParam.integer().toJson(), {'type': 'integer'});
    });

    test('emits numeric bounds and default using JSON Schema names', () {
      const param = ExtensionParam.integer(
        description: 'A slide index.',
        defaultValue: 0,
        minimum: 0,
        maximum: 99,
        exclusiveMinimum: -1,
        exclusiveMaximum: 100,
        multipleOf: 1,
      );
      expect(param.toJson(), {
        'description': 'A slide index.',
        'default': 0,
        'type': 'integer',
        'minimum': 0,
        'maximum': 99,
        'exclusiveMinimum': -1,
        'exclusiveMaximum': 100,
        'multipleOf': 1,
      });
    });
  });

  group('ExtensionParam.number', () {
    test('emits "type": "number" with no other fields by default', () {
      expect(const ExtensionParam.number().toJson(), {'type': 'number'});
    });

    test('preserves doubles through "default", bounds, and multipleOf', () {
      const param = ExtensionParam.number(
        defaultValue: 1.5,
        minimum: 0.1,
        maximum: 10.5,
        multipleOf: 0.5,
      );
      expect(param.toJson(), {
        'default': 1.5,
        'type': 'number',
        'minimum': 0.1,
        'maximum': 10.5,
        'multipleOf': 0.5,
      });
    });
  });

  group('ExtensionParam.boolean', () {
    test('emits "type": "boolean" with no other fields by default', () {
      expect(const ExtensionParam.boolean().toJson(), {'type': 'boolean'});
    });

    test('emits description and default when set', () {
      const param = ExtensionParam.boolean(
        description: 'Animate?',
        defaultValue: true,
      );
      expect(param.toJson(), {
        'description': 'Animate?',
        'default': true,
        'type': 'boolean',
      });
    });
  });

  test('end-to-end: typed DSL produces the same wire JSON as a raw map', () {
    // Faithful reproduction of the example app's previous raw-map shape
    // and the typed DSL replacement. Confirms the wire format is unchanged.
    const expected = {
      'type': 'object',
      'properties': {
        'page': {
          'description': 'Page name. One of: home, profile, settings',
          'type': 'string',
          'enum': ['home', 'profile', 'settings'],
        },
      },
      'required': ['page'],
    };

    const schema = ExtensionInputSchema(
      properties: {
        'page': ExtensionParam.string(
          description: 'Page name. One of: home, profile, settings',
          enumValues: ['home', 'profile', 'settings'],
        ),
      },
      required: ['page'],
    );

    expect(schema.toJson(), expected);
  });
}
