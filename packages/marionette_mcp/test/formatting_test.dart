import 'package:marionette_mcp/src/formatting.dart';
import 'package:test/test.dart';

void main() {
  group('coveredAppWarning', () {
    test('warns while the app is not in front', () {
      for (final state in ['inactive', 'paused', 'hidden']) {
        expect(
          coveredAppWarning({'elements': [], 'appLifecycleState': state}),
          allOf(contains('lifecycle: $state'), contains('native_get_elements')),
        );
      }
    });

    test('names the given native command', () {
      expect(
        coveredAppWarning(
          {'appLifecycleState': 'paused'},
          nativeElements: 'marionette native-get-elements',
        ),
        contains('marionette native-get-elements'),
      );
    });

    test('says nothing when resumed or not reported (older binding)', () {
      expect(coveredAppWarning({'appLifecycleState': 'resumed'}), isNull);
      expect(coveredAppWarning({'elements': []}), isNull);
    });
  });
}
