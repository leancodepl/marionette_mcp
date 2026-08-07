import 'package:marionette_mcp/src/native_service/supported_platform.dart';
import 'package:test/test.dart';

void main() {
  group('SupportedPlatform', () {
    test('tryParse accepts wire names case-insensitively', () {
      expect(SupportedPlatform.tryParse('android'), SupportedPlatform.android);
      expect(SupportedPlatform.tryParse(' IOS '), SupportedPlatform.ios);
      expect(SupportedPlatform.tryParse('Web'), SupportedPlatform.web);
    });

    test('tryParse returns null for unknown values', () {
      expect(SupportedPlatform.tryParse('macos'), isNull);
      expect(SupportedPlatform.tryParse(null), isNull);
      expect(SupportedPlatform.tryParse(''), isNull);
    });

    test('quotedWireNames lists all platforms', () {
      expect(
        SupportedPlatform.quotedWireNames,
        '"android", "ios", or "web"',
      );
    });
  });
}
