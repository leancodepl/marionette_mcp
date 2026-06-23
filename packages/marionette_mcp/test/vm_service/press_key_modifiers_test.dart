import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

void main() {
  group('invalidModifiersError', () {
    test('returns null for null or empty input', () {
      expect(invalidModifiersError(null), isNull);
      expect(invalidModifiersError(''), isNull);
      expect(invalidModifiersError('   '), isNull);
    });

    test('accepts every supported modifier, case-insensitively', () {
      expect(invalidModifiersError('control'), isNull);
      expect(invalidModifiersError('shift,alt,meta'), isNull);
      expect(invalidModifiersError('Control, SHIFT'), isNull);
    });

    test('reports a single unsupported modifier', () {
      final error = invalidModifiersError('hyper');
      expect(error, contains('Unsupported modifier: hyper'));
      expect(error, contains('control, shift, alt, meta'));
    });

    test('reports multiple unsupported modifiers and pluralizes', () {
      final error = invalidModifiersError('control,hyper,fn');
      expect(error, contains('Unsupported modifiers: hyper, fn'));
    });
  });

  group('VmServiceConnector.pressKey', () {
    test('throws ArgumentError before connecting when a modifier is invalid',
        () {
      expect(
        () => VmServiceConnector().pressKey('a', modifiers: 'bogus'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
