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

  group('ElementTreeFinder identifier extraction', () {
    testWidgets(
        'Semantics with only an identifier (no label/value, no key) is '
        'surfaced with its identifier so agents can discover it',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Semantics(
                identifier: 'submit_button',
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Submit'),
                ),
              ),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements.any(
          (e) =>
              e['type'] == 'Semantics' && e['identifier'] == 'submit_button',
        ),
        isTrue,
        reason: 'An identifier-only Semantics wrapper must appear in '
            'get_interactive_elements — mirroring how a keyed wrapper is '
            'surfaced — otherwise agents cannot discover the identifier they '
            'are told to match on',
      );
    });

    testWidgets('Semantics with an empty identifier is not reported',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              identifier: '',
              child: Container(width: 100, height: 100, color: Colors.green),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(
        elements.any((e) => e['type'] == 'Semantics'),
        isFalse,
        reason: 'An empty identifier carries no content and should stay quiet, '
            'consistent with the label/value discovery contract',
      );
    });
  });
}
