import 'dart:convert';

import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:test/test.dart';

void main() {
  group('WidgetMatcher.fromJson', () {
    test('returns FocusedElementMatcher for focused matcher', () {
      final matcher = WidgetMatcher.fromJson({'focused': true});

      expect(matcher, isA<FocusedElementMatcher>());
    });

    test('focused matcher has highest precedence', () {
      final matcher = WidgetMatcher.fromJson({
        'focused': true,
        'key': 'name_field',
      });

      expect(matcher, isA<FocusedElementMatcher>());
    });

    test('returns IdentifierMatcher for identifier matcher', () {
      final matcher = WidgetMatcher.fromJson({'identifier': 'submit_button'});

      expect(matcher, isA<IdentifierMatcher>());
      expect((matcher as IdentifierMatcher).identifierValue, 'submit_button');
    });

    test('key takes precedence over identifier', () {
      final matcher = WidgetMatcher.fromJson({
        'key': 'submit_key',
        'identifier': 'submit_id',
      });

      expect(matcher, isA<KeyMatcher>());
    });

    test('identifier takes precedence over text', () {
      final matcher = WidgetMatcher.fromJson({
        'identifier': 'submit_id',
        'text': 'Submit',
      });

      expect(matcher, isA<IdentifierMatcher>());
    });

    test('ancestor_keys does not select the target matcher', () {
      final matcher = WidgetMatcher.fromJson({
        'key': 'join_button',
        'ancestor_keys': jsonEncode(['grid.cell_2']),
      });

      expect(matcher, isA<KeyMatcher>());
      expect((matcher as KeyMatcher).keyValue, 'join_button');
    });

    test('ancestor_keys alone is not a valid matcher', () {
      expect(
        () => WidgetMatcher.fromJson({
          'ancestor_keys': jsonEncode(['grid.cell_2']),
        }),
        throwsArgumentError,
      );
    });

    test('focused=false falls through to other matchers', () {
      final matcher = WidgetMatcher.fromJson({
        'focused': false,
        'key': 'name_field',
      });

      expect(matcher, isA<KeyMatcher>());
      expect((matcher as KeyMatcher).keyValue, 'name_field');
    });

    test('focused="false" falls through to other matchers', () {
      final matcher = WidgetMatcher.fromJson({
        'focused': 'false',
        'key': 'name_field',
      });

      expect(matcher, isA<KeyMatcher>());
    });

    test('focused="true" selects FocusedElementMatcher', () {
      final matcher = WidgetMatcher.fromJson({'focused': 'true'});

      expect(matcher, isA<FocusedElementMatcher>());
    });

    test('rejects invalid focused flag values with ArgumentError', () {
      for (final bad in [
        {'focused': 'maybe'},
        {'focused': null, 'key': 'name_field'},
      ]) {
        expect(
          () => WidgetMatcher.fromJson(bad),
          throwsArgumentError,
        );
      }
    });

    test('rejects non-string selector values with ArgumentError', () {
      for (final badJson in [
        {'key': null},
        {'key': 123},
        {'identifier': null},
        {'text': 42},
        {'type': false},
      ]) {
        expect(
          () => WidgetMatcher.fromJson(badJson),
          throwsArgumentError,
        );
      }
    });

    test('rejects non-finite or null coordinates with ArgumentError', () {
      for (final badCoords in [
        {'x': 'NaN', 'y': '10'},
        {'x': '10', 'y': 'Infinity'},
        {'x': null, 'y': 10, 'key': 'name_field'},
        {'x': 10, 'y': null, 'key': 'name_field'},
      ]) {
        expect(
          () => WidgetMatcher.fromJson(badCoords),
          throwsArgumentError,
        );
      }
    });
  });

  group('WidgetMatcher.ancestorsFromJson', () {
    test('is empty when ancestor_keys is absent', () {
      expect(WidgetMatcher.ancestorsFromJson({'key': 'join_button'}), isEmpty);
    });

    test('is empty for an empty ancestor_keys array', () {
      expect(
        WidgetMatcher.ancestorsFromJson(
            {'ancestor_keys': jsonEncode(<String>[])}),
        isEmpty,
      );
    });

    test('parses a single ancestor key', () {
      final ancestors = WidgetMatcher.ancestorsFromJson({
        'key': 'join_button',
        'ancestor_keys': jsonEncode(['grid.cell_2']),
      });

      expect(ancestors.map((m) => m.keyValue), ['grid.cell_2']);
    });

    test('preserves outermost-first order of a nested chain', () {
      final ancestors = WidgetMatcher.ancestorsFromJson({
        'ancestor_keys': jsonEncode(['session_2', 'grid.cell_2']),
      });

      expect(ancestors.map((m) => m.keyValue), ['session_2', 'grid.cell_2']);
    });

    test('rejects a malformed ancestor_keys payload', () {
      expect(
        () => WidgetMatcher.ancestorsFromJson({'ancestor_keys': 'grid.cell_2'}),
        throwsArgumentError,
      );
    });
  });

  group('FocusedElementMatcher', () {
    test('serializes to focused json', () {
      const matcher = FocusedElementMatcher();

      expect(matcher.toJson(), {'focused': true});
    });
  });

  group('IdentifierMatcher', () {
    test('serializes to identifier json', () {
      const matcher = IdentifierMatcher('submit_button');

      expect(matcher.toJson(), {'identifier': 'submit_button'});
    });

    test('round-trips through fromJson/toJson', () {
      const original = IdentifierMatcher('submit_button');
      final restored = WidgetMatcher.fromJson(original.toJson());

      expect(restored, isA<IdentifierMatcher>());
      expect((restored as IdentifierMatcher).identifierValue, 'submit_button');
    });
  });
}
