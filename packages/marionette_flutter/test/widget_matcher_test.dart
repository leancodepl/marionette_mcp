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

    test('within_key does not select the target matcher', () {
      final matcher = WidgetMatcher.fromJson({
        'key': 'join_button',
        'within_key': 'grid.cell_2',
      });

      expect(matcher, isA<KeyMatcher>());
      expect((matcher as KeyMatcher).keyValue, 'join_button');
    });

    test('within_key alone is not a valid matcher', () {
      expect(
        () => WidgetMatcher.fromJson({'within_key': 'grid.cell_2'}),
        throwsArgumentError,
      );
    });
  });

  group('WidgetMatcher.scopeFromJson', () {
    test('returns null when within_key is absent', () {
      expect(WidgetMatcher.scopeFromJson({'key': 'join_button'}), isNull);
    });

    test('returns a KeyMatcher for within_key', () {
      final scope = WidgetMatcher.scopeFromJson({
        'key': 'join_button',
        'within_key': 'grid.cell_2',
      });

      expect(scope, isA<KeyMatcher>());
      expect(scope!.keyValue, 'grid.cell_2');
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
