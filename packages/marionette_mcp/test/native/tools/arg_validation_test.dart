import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:test/test.dart';

enum _Key { volumeUp }

void main() {
  group('enumArg', () {
    test('matches a camelCase name in any case', () {
      expect(enumArg({'key': 'volumeup'}, 'key', _Key.values), _Key.volumeUp);
    });
  });
}
