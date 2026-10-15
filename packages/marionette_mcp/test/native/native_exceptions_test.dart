import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/xpath.dart';
import 'package:test/test.dart';

void main() {
  group('NativeLaneException', () {
    test('toString appends the hint for the agent', () {
      expect(
        const NativeElementNotFoundException('text="Allow"').toString(),
        'No native element with text="Allow".\n'
        'Hint: Call native_get_elements and retry with a value from its '
        'output.',
      );
    });

    test('not connected points to native_connect', () {
      expect(
        const NativeNotConnectedException().toString(),
        contains('native_connect'),
      );
    });

    test('bootstrap exceptions name the platform and stage', () {
      final android = AndroidBootstrapException(
        AndroidBootstrapFailure.adbMissing,
        'adb was not found',
      );
      final ios = IosBootstrapException(
        IosBootstrapFailure.noBootedSimulator,
        'No booted iOS Simulator found.',
      );

      expect(android.hint, AndroidBootstrapFailure.adbMissing.hint);
      expect(
        android.toString(),
        startsWith('Android native bootstrap failed (adbMissing): '
            'adb was not found\nHint: '),
      );
      expect(
        ios.toString(),
        startsWith('iOS native bootstrap failed (noBootedSimulator): '),
      );
    });

    test('an explicit hint overrides the stage default', () {
      final error = IosBootstrapException(
        IosBootstrapFailure.launch,
        'failed',
        hint: 'custom',
      );

      expect(error.hint, 'custom');
    });

    test('every stage has a non-empty default hint', () {
      for (final failure in [
        ...AndroidBootstrapFailure.values.map((f) => f.hint),
        ...IosBootstrapFailure.values.map((f) => f.hint),
      ]) {
        expect(failure, isNotEmpty);
      }
    });
  });

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
