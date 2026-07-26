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

    test('single identifier arg', () {
      expect(
        buildMatcherFromArgs(identifier: 'submit_button'),
        equals({'identifier': 'submit_button'}),
      );
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

    test('within key arg', () {
      expect(
        buildMatcherFromArgs(key: 'join_button', withinKey: 'grid.cell_2'),
        equals({'key': 'join_button', 'within_key': 'grid.cell_2'}),
      );
    });
  });

  group('hasSelector', () {
    test('empty matcher has no selector', () {
      expect(hasSelector(buildMatcherFromArgs()), isFalse);
    });

    test('a scope alone is not a selector', () {
      expect(
        hasSelector(buildMatcherFromArgs(withinKey: 'grid.cell_2')),
        isFalse,
      );
    });

    test('a scoped key is a selector', () {
      expect(
        hasSelector(
          buildMatcherFromArgs(key: 'join_button', withinKey: 'grid.cell_2'),
        ),
        isTrue,
      );
    });
  });
}
