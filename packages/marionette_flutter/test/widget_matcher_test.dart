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
  });

  group('FocusedElementMatcher', () {
    test('serializes to focused json', () {
      const matcher = FocusedElementMatcher();

      expect(matcher.toJson(), {'focused': true});
    });
  });
}
