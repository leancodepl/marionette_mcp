import 'package:marionette_mcp/src/native_service/xpath.dart';
import 'package:test/test.dart';

void main() {
  group('xpathLiteral', () {
    test('wraps plain text in single quotes', () {
      expect(xpathLiteral('Allow'), "'Allow'");
    });

    test('uses double quotes for an apostrophe', () {
      expect(xpathLiteral("Don't Allow"), '"Don\'t Allow"');
    });

    test('uses concat() when both quote characters are present', () {
      expect(
        xpathLiteral('Say "hi" don\'t'),
        'concat(\'Say "hi" don\', "\'", \'t\')',
      );
    });

    test('leaves typographic apostrophes alone', () {
      expect(xpathLiteral('Don’t Allow'), "'Don’t Allow'");
    });

    test('handles the empty string', () {
      expect(xpathLiteral(''), "''");
    });
  });
}
