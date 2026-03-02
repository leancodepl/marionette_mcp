import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:test/test.dart';

void main() {
  group('buildMatcherFromArgs', () {
    test('all null args returns empty map', () {
      expect(buildMatcherFromArgs(), isEmpty);
    });

    test('single key arg', () {
      expect(buildMatcherFromArgs(key: 'btn'), equals({'key': 'btn'}));
    });

    test('single text arg', () {
      expect(buildMatcherFromArgs(text: 'Submit'), equals({'text': 'Submit'}));
    });

    test('coordinates only', () {
      expect(
        buildMatcherFromArgs(x: 100, y: 200),
        equals({'x': 100, 'y': 200}),
      );
    });

    test('combined key and text', () {
      final result = buildMatcherFromArgs(key: 'btn', text: 'Submit');
      expect(result, equals({'key': 'btn', 'text': 'Submit'}));
    });

    test('type arg', () {
      expect(
        buildMatcherFromArgs(type: 'ElevatedButton'),
        equals({'type': 'ElevatedButton'}),
      );
    });
  });
}
