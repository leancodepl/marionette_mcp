import 'package:marionette_mcp/src/vm_service/tools/arg_coercion.dart';
import 'package:test/test.dart';

void main() {
  group('coerceToStringMap', () {
    test('passes string values through unchanged', () {
      expect(coerceToStringMap({'k': 'v'}), {'k': 'v'});
    });

    test('stringifies numbers and booleans', () {
      expect(
        coerceToStringMap({'i': 42, 'd': 1.5, 'b': true}),
        {'i': '42', 'd': '1.5', 'b': 'true'},
      );
    });

    test('jsonEncodes nested structures', () {
      expect(
        coerceToStringMap({
          'list': [1, 2],
          'map': {'x': 1},
        }),
        {'list': '[1,2]', 'map': '{"x":1}'},
      );
    });

    test('replaces null with the empty string', () {
      expect(coerceToStringMap({'k': null}), {'k': ''});
    });
  });
}
