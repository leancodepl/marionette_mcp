import 'package:marionette_cli/src/cli/commands/get_interactive_elements_command.dart';
import 'package:test/test.dart';

void main() {
  test('formats versioned response context', () {
    final output = formatInteractiveElementsCommandOutput({
      'schemaVersion': 1,
      'context': {'route': '/checkout'},
      'elements': <Object?>[],
    });

    expect(output, contains('Schema version: 1'));
    expect(output, contains('Context: {"route":"/checkout"}'));
    expect(output, contains('Found 0 interactive element(s):'));
  });
}
