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

    test('ancestor keys are JSON-encoded for the string-only wire', () {
      expect(
        buildMatcherFromArgs(
          key: 'join_button',
          ancestorKeys: ['session_2', 'grid.cell_3'],
        ),
        equals({
          'key': 'join_button',
          'ancestor_keys': '["session_2","grid.cell_3"]',
        }),
      );
    });

    test('an empty ancestor chain is omitted', () {
      expect(
        buildMatcherFromArgs(key: 'join_button', ancestorKeys: const []),
        equals({'key': 'join_button'}),
      );
    });
  });

  group('hasSelector', () {
    test('empty matcher has no selector', () {
      expect(hasSelector(buildMatcherFromArgs()), isFalse);
    });

    test('a scope alone is not a selector', () {
      expect(
        hasSelector(buildMatcherFromArgs(ancestorKeys: ['grid.cell_2'])),
        isFalse,
      );
    });

    test('a scoped key is a selector', () {
      expect(
        hasSelector(
          buildMatcherFromArgs(
            key: 'join_button',
            ancestorKeys: ['grid.cell_2'],
          ),
        ),
        isTrue,
      );
    });
  });

  group('buildValidatedMatcherFromArgs', () {
    Never throwUsage(String message) => throw ArgumentError(message);

    test('rejects --x without --y', () {
      expect(
        () => buildValidatedMatcherFromArgs(x: '10', onUsageError: throwUsage),
        throwsArgumentError,
      );
    });

    test('rejects --y without --x', () {
      expect(
        () => buildValidatedMatcherFromArgs(y: '20', onUsageError: throwUsage),
        throwsArgumentError,
      );
    });

    test('rejects non-numeric or non-finite coordinates', () {
      for (final bad in const ['abc', 'NaN', 'Infinity']) {
        expect(
          () => buildValidatedMatcherFromArgs(
            x: bad,
            y: '20',
            onUsageError: throwUsage,
          ),
          throwsArgumentError,
        );
      }
    });

    test('builds coordinate matcher for valid finite x and y', () {
      expect(
        buildValidatedMatcherFromArgs(
          x: '10.5',
          y: '20',
          onUsageError: throwUsage,
        ),
        equals({'x': 10.5, 'y': 20}),
      );
    });
  });
}
