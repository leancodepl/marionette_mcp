import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  group('WidgetMatcher.fromJson', () {
    test('returns CoordinatesMatcher for coordinates', () {
      final matcher = WidgetMatcher.fromJson({'x': '100.0', 'y': '200.0'});

      expect(matcher, isA<CoordinatesMatcher>());
      expect(matcher.toJson(), {'x': 100.0, 'y': 200.0});
    });

    test('returns KeyMatcher for key matcher', () {
      final matcher = WidgetMatcher.fromJson({'key': 'test_button'});

      expect(matcher, isA<KeyMatcher>());
      expect(matcher.toJson(), {'key': 'test_button'});
    });

    test('returns TextMatcher for text matcher', () {
      final matcher = WidgetMatcher.fromJson({'text': 'Submit'});

      expect(matcher, isA<TextMatcher>());
      expect(matcher.toJson(), {'text': 'Submit'});
    });

    test('returns TypeStringMatcher for type matcher', () {
      final matcher = WidgetMatcher.fromJson({'type': 'ElevatedButton'});

      expect(matcher, isA<TypeStringMatcher>());
      expect(matcher.toJson(), {'type': 'ElevatedButton'});
    });

    test('coordinates matcher has highest precedence', () {
      final matcher = WidgetMatcher.fromJson({
        'x': '100.0',
        'y': '200.0',
        'key': 'test_button',
        'text': 'Submit',
        'type': 'ElevatedButton',
      });

      expect(matcher, isA<CoordinatesMatcher>());
    });

    test('key matcher has precedence over text and type', () {
      final matcher = WidgetMatcher.fromJson({
        'key': 'test_button',
        'text': 'Submit',
        'type': 'ElevatedButton',
      });

      expect(matcher, isA<KeyMatcher>());
    });

    test('text matcher has precedence over type', () {
      final matcher = WidgetMatcher.fromJson({
        'text': 'Submit',
        'type': 'ElevatedButton',
      });

      expect(matcher, isA<TextMatcher>());
    });

    test('throws when no valid matcher field provided', () {
      expect(
        () => WidgetMatcher.fromJson({}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CoordinatesMatcher', () {
    test('serializes to coordinates json', () {
      const matcher = CoordinatesMatcher(100, 200);

      expect(matcher.toJson(), {'x': 100.0, 'y': 200.0});
    });

    test('creates from json with string coordinates', () {
      final matcher = CoordinatesMatcher.fromJson({'x': '100.5', 'y': '200.5'});

      expect(matcher.x, 100.5);
      expect(matcher.y, 200.5);
    });

    test('provides offset property', () {
      const matcher = CoordinatesMatcher(100, 200);

      expect(matcher.offset, const Offset(100, 200));
    });
  });

  group('KeyMatcher', () {
    test('serializes to key json', () {
      const matcher = KeyMatcher('test_button');

      expect(matcher.toJson(), {'key': 'test_button'});
    });

    test('creates from json', () {
      final matcher = KeyMatcher.fromJson({'key': 'test_button'});

      expect(matcher.keyValue, 'test_button');
    });
  });

  group('TextMatcher', () {
    test('serializes to text json', () {
      const matcher = TextMatcher('Submit');

      expect(matcher.toJson(), {'text': 'Submit'});
    });

    test('creates from json', () {
      final matcher = TextMatcher.fromJson({'text': 'Submit'});

      expect(matcher.text, 'Submit');
    });
  });

  group('TypeStringMatcher', () {
    test('serializes to type json', () {
      const matcher = TypeStringMatcher('ElevatedButton');

      expect(matcher.toJson(), {'type': 'ElevatedButton'});
    });

    test('creates from json', () {
      final matcher = TypeStringMatcher.fromJson({'type': 'ElevatedButton'});

      expect(matcher.typeName, 'ElevatedButton');
    });
  });
}
