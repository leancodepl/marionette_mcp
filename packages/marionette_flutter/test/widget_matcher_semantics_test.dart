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
}
