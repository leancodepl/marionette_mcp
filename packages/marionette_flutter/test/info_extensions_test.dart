import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';

void main() {
  group('parseCompactionParam', () {
    test('reads each CompactionMode name off the wire', () {
      // The VM service hands every param to the app as a string, so the sender
      // sends the enum name instead of relying on the transport's coercion.
      expect(
        parseCompactionParam({'compaction': 'none'}).value,
        CompactionMode.none,
      );
      expect(
        parseCompactionParam({'compaction': 'compact'}).value,
        CompactionMode.compact,
      );
    });

    test('an absent key selects the app default', () {
      final parsed = parseCompactionParam({});

      expect(parsed.value, isNull);
      expect(parsed.error, isNull);
    });

    test('rejects an unknown mode, naming the valid ones', () {
      final parsed = parseCompactionParam({'compaction': 'ultra'});

      expect(parsed.value, isNull);
      expect(parsed.error, isA<MarionetteExtensionInvalidParams>());
      expect(
        (parsed.error! as MarionetteExtensionInvalidParams).detail,
        contains('must be "none" or "compact", got "ultra"'),
      );
    });
  });
}
