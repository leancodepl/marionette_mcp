import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _configuration = MarionetteConfiguration();

void main() {
  group('TextMatcher with Semantics wrappers', () {
    testWidgets(
        'resolves to the inner Text, not the Semantics wrapper that shares '
        'the same label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Semantics(
                label: 'submit',
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('submit'),
                ),
              ),
            ),
          ),
        ),
      );

      final element = WidgetFinder().findHittableElement(
        const TextMatcher('submit'),
        _configuration,
      );

      expect(element, isNotNull);
      expect(
        element!.widget.runtimeType,
        Text,
        reason: 'TextMatcher must resolve to the inner Text widget, not the '
            'Semantics wrapper — otherwise tap/scroll_to/enter_text are '
            'redirected to the wrapper node and the inner control never '
            'receives the gesture',
      );
    });

    testWidgets(
        'does not match a Semantics-only label '
        '(discovery-only contract)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Semantics(
                label: 'progress label',
                child: Container(width: 100, height: 100, color: Colors.blue),
              ),
            ),
          ),
        ),
      );

      final element = WidgetFinder().findHittableElement(
        const TextMatcher('progress label'),
        _configuration,
      );

      expect(
        element,
        isNull,
        reason: 'Semantics annotations are surfaced for discovery only — '
            'they must not be matchable, otherwise tap would target the '
            'Semantics wrapper instead of the underlying widget',
      );
    });

    testWidgets('does not match a combined Semantics label/value either',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Semantics(
                label: 'Volume',
                value: '70%',
                child: Container(width: 100, height: 100, color: Colors.blue),
              ),
            ),
          ),
        ),
      );

      final element = WidgetFinder().findHittableElement(
        const TextMatcher('Volume: 70%'),
        _configuration,
      );

      expect(
        element,
        isNull,
        reason: 'The combined "label: value" string is a discovery-only '
            'projection — TextMatcher must not see it, otherwise an agent '
            'reading get_interactive_elements could tap on a Semantics '
            'wrapper by accident',
      );
    });
  });

  group('IdentifierMatcher with Semantics wrappers', () {
    testWidgets(
        'matches the Semantics wrapper and is hittable through its child',
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

      final element = WidgetFinder().findHittableElement(
        const IdentifierMatcher('submit_button'),
        _configuration,
      );

      expect(
        element,
        isNotNull,
        reason: 'A Semantics identifier is an explicit, unique selector and '
            'must be matchable — and hittable, since the wrapper shares the '
            "child's bounds so the tap lands on the inner control",
      );
      expect(element!.widget, isA<Semantics>());
      expect(
        (element.widget as Semantics).properties.identifier,
        'submit_button',
      );

      // The matched Semantics wrapper shares the bounds of its child, so a
      // tap at its center reaches the underlying ElevatedButton.
      final semanticsBox = element.renderObject! as RenderBox;
      final buttonBox = tester.renderObject<RenderBox>(
        find.byType(ElevatedButton),
      );
      expect(semanticsBox.size, buttonBox.size);
      expect(
        semanticsBox.localToGlobal(Offset.zero),
        buttonBox.localToGlobal(Offset.zero),
      );
    });

    testWidgets('does not match a Semantics widget without an identifier',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Semantics(
                label: 'submit_button',
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Submit'),
                ),
              ),
            ),
          ),
        ),
      );

      final element = WidgetFinder().findElement(
        const IdentifierMatcher('submit_button'),
        _configuration,
      );

      expect(
        element,
        isNull,
        reason: 'IdentifierMatcher must match the Semantics identifier, not '
            'the label — a label that happens to equal the identifier value '
            'must not produce a false match',
      );
    });

    testWidgets(
        'matches Text.semanticsIdentifier, which desugars to a Semantics '
        'wrapper, and is hittable inside an interactive ancestor',
        (tester) async {
      // Text(semanticsIdentifier: ...) builds a Semantics(identifier: ...)
      // wrapper internally, so the same matcher mechanism covers it — no
      // per-widget special case needed.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Submit', semanticsIdentifier: 'submit_btn'),
              ),
            ),
          ),
        ),
      );

      final element = WidgetFinder().findHittableElement(
        const IdentifierMatcher('submit_btn'),
        _configuration,
      );

      expect(
        element,
        isNotNull,
        reason: 'Text.semanticsIdentifier forwards to a generated Semantics '
            'wrapper, so identifier matching must find it; inside a button it '
            'is hittable so tap/enter_text reach the control',
      );
      expect(element!.widget, isA<Semantics>());
      expect(
        (element.widget as Semantics).properties.identifier,
        'submit_btn',
      );
    });
  });
}
