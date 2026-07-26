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

    test('forwards within_key alongside the selector', () {
      expect(
        buildMatcher({'key': 'join_button', 'within_key': 'grid.cell_2'}),
        equals({'key': 'join_button', 'within_key': 'grid.cell_2'}),
      );
    });

    test('omits within_key when it is absent', () {
      expect(
          buildMatcher({'key': 'join_button'}), equals({'key': 'join_button'}));
    });
  });

  group('hasSelector', () {
    test('empty matcher has no selector', () {
      expect(hasSelector(buildMatcher({})), isFalse);
    });

    test('a scope alone is not a selector', () {
      expect(hasSelector(buildMatcher({'within_key': 'grid.cell_2'})), isFalse);
    });

    test('a scoped key is a selector', () {
      expect(
        hasSelector(
          buildMatcher({'key': 'join_button', 'within_key': 'grid.cell_2'}),
        ),
        isTrue,
      );
    });
  });
}
