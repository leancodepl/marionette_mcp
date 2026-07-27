import 'package:marionette_mcp/src/formatting.dart';
import 'package:test/test.dart';

void main() {
  group('buildMatcher', () {
    test('forwards key and identifier', () {
      expect(
        buildMatcher({'key': 'join_button', 'identifier': 'join'}),
        equals({'key': 'join_button', 'identifier': 'join'}),
      );
    });

    test('flattens coordinates', () {
      expect(
        buildMatcher({
          'coordinates': <String, dynamic>{'x': 10, 'y': 20},
        }),
        equals({'x': 10, 'y': 20}),
      );
    });

    test('encodes ancestor_keys as JSON for the string-only wire', () {
      expect(
        buildMatcher({
          'key': 'join_button',
          'ancestor_keys': ['session_2', 'grid.cell_3'],
        }),
        equals({
          'key': 'join_button',
          'ancestor_keys': '["session_2","grid.cell_3"]',
        }),
      );
    });

    test('omits ancestor_keys when it is absent', () {
      expect(
        buildMatcher({'key': 'join_button'}),
        equals({'key': 'join_button'}),
      );
    });

    test('omits an empty ancestor_keys array', () {
      expect(
        buildMatcher({'key': 'join_button', 'ancestor_keys': <String>[]}),
        equals({'key': 'join_button'}),
        reason: 'an empty chain means no scope, so nothing should go on the '
            'wire and behavior must match omitting the field',
      );
    });
  });

  group('hasSelector', () {
    test('empty matcher has no selector', () {
      expect(hasSelector(buildMatcher({})), isFalse);
    });

    test('a scope alone is not a selector', () {
      expect(
        hasSelector(buildMatcher({
          'ancestor_keys': ['grid.cell_2'],
        })),
        isFalse,
      );
    });

    test('a scoped key is a selector', () {
      expect(
        hasSelector(buildMatcher({
          'key': 'join_button',
          'ancestor_keys': ['grid.cell_2'],
        })),
        isTrue,
      );
    });
  });
}
