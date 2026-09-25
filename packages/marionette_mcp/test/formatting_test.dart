import 'package:marionette_mcp/src/formatting.dart';
import 'package:test/test.dart';

void main() {
  test('versioned response keeps context and elements in text output', () {
    final output = formatInteractiveElementsResponse(<String, dynamic>{
      'schemaVersion': 1,
      'context': <String, Object?>{'route': '/checkout', 'screen': 'Checkout'},
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'Button', 'text': 'Continue'},
      ],
    });

    expect(output, contains('Schema version: 1'));
    expect(output, contains('"route":"/checkout"'));
    expect(output, contains('Found 1 interactive element(s)'));
    expect(output, contains('Type: Button, Text: "Continue"'));
  });

  test('legacy elements-only response keeps the previous text shape', () {
    final output = formatInteractiveElementsResponse(<String, dynamic>{
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'Button'},
      ],
    });

    expect(output, startsWith('Found 1 interactive element(s):\n\n'));
    expect(output, isNot(contains('Schema version:')));
    expect(output, isNot(contains('Context:')));
  });

  test('requires the core elements payload', () {
    expect(
      () => formatInteractiveElementsResponse(<String, dynamic>{
        'schemaVersion': 1,
      }),
      throwsA(isA<TypeError>()),
    );
  });
}
