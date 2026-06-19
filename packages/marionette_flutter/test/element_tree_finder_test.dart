import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';

const _configuration = MarionetteConfiguration();
const _finder = ElementTreeFinder(_configuration);

void main() {
  group('ElementTreeFinder text extraction', () {
    testWidgets('plain Text widget surfaces its data', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('hello world'))),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements.any((e) => e['type'] == 'Text' && e['text'] == 'hello world'),
        isTrue,
      );
    });

    testWidgets('Text.rich joins TextSpan tree via toPlainText',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text.rich(
              TextSpan(
                children: const [
                  TextSpan(text: 'Hello '),
                  TextSpan(
                      text: 'bold',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: ' world'),
                ],
              ),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements
            .any((e) => e['type'] == 'Text' && e['text'] == 'Hello bold world'),
        isTrue,
      );
    });

    testWidgets(
        'Semantics with explicit label is reported as a discoverable element',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              label: 'summary card: hello world',
              excludeSemantics: true,
              child: Text.rich(const TextSpan(text: 'Hello world')),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements.any(
          (e) =>
              e['type'] == 'Semantics' &&
              e['text'] == 'summary card: hello world',
        ),
        isTrue,
        reason:
            'Semantics widgets with explicit labels should appear in get_interactive_elements',
      );
    });

    testWidgets('Semantics falls back to value when label is empty',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              value: 'progress 70%',
              child: Container(width: 100, height: 100, color: Colors.blue),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements.any(
            (e) => e['type'] == 'Semantics' && e['text'] == 'progress 70%'),
        isTrue,
      );
    });

    testWidgets(
        'Semantics with both label and value joins them as "label: value"',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              label: 'Volume',
              value: '70%',
              child: Container(width: 100, height: 100, color: Colors.blue),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements.any(
          (e) => e['type'] == 'Semantics' && e['text'] == 'Volume: 70%',
        ),
        isTrue,
        reason:
            'When both label and value are set, the discovery output should '
            'preserve the dynamic state instead of dropping value',
      );
    });

    testWidgets('Semantics without label or value is not reported',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              container: true,
              child: Container(width: 100, height: 100, color: Colors.red),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements.any((e) => e['type'] == 'Semantics'),
        isFalse,
        reason: 'Semantics with no explicit text should not pollute the output',
      );
    });
  });

  group('ElementTreeFinder compact mode', () {
    testWidgets('drops style/object blobs but keeps primitive state and bounds',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                ),
                onPressed: () {},
                child: const Text('Submit'),
              ),
            ),
          ),
        ),
      );

      final verbose = _finder.findInteractiveElements();
      final verboseButton =
          verbose.firstWhere((e) => e['type'] == 'ElevatedButton');
      expect(verboseButton.containsKey('style'), isTrue,
          reason: 'verbose mode (default) still dumps the ButtonStyle blob');

      final compact = _finder.findInteractiveElements(compact: true);
      final compactButton =
          compact.firstWhere((e) => e['type'] == 'ElevatedButton');
      expect(compactButton.containsKey('style'), isFalse,
          reason: 'compact drops the ButtonStyle object blob');
      expect(compactButton.containsKey('focusNode'), isFalse,
          reason: 'compact drops the FocusNode object blob');
      expect(compactButton['enabled'], isNotNull,
          reason: 'compact keeps the primitive enabled flag');
      expect(compactButton.containsKey('bounds'), isTrue);
      expect(compactButton['visible'], isTrue);
    });

    testWidgets(
        'keeps generic DiagnosticsProperty<bool> state and preserves '
        'TextField label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: TextEditingController(),
              enabled: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ),
        ),
      );

      final compact = _finder.findInteractiveElements(compact: true);
      final field = compact.firstWhere((e) => e['type'] == 'TextField');

      // These are declared as DiagnosticsProperty<bool> by TextField, so a
      // node-type filter would wrongly drop them — value-type keeps them.
      expect(field['obscureText'], 'true');
      expect(field['enabled'], isNotNull);
      // Object blobs are dropped.
      expect(field.containsKey('decoration'), isFalse);
      expect(field.containsKey('controller'), isFalse);
      expect(field.containsKey('style'), isFalse);
      // Label is preserved from the dropped InputDecoration.
      expect(field['label'], 'Email');
    });
  });
}
