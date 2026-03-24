import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

void main() {
  const configuration = MarionetteConfiguration();

  group('TextInputSimulator.enterText', () {
    testWidgets('triggers TextField onChanged and updates caret by key', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'seed');
      String changedValue = '';

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey('name_field'),
              controller: controller,
              onChanged: (value) => changedValue = value,
            ),
          ),
        ),
      );

      final simulator = TextInputSimulator(WidgetFinder());
      await simulator.enterText(
        const KeyMatcher('name_field'),
        'Hello',
        configuration,
      );
      await tester.pump();

      expect(changedValue, 'Hello');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    });

    testWidgets('triggers TextFormField onChanged and validator updates by key',
        (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'seed-email');
      String changedValue = '';

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              autovalidateMode: AutovalidateMode.always,
              child: TextFormField(
                key: const ValueKey('email_field'),
                controller: controller,
                validator: (value) {
                  if (value == null || !value.contains('@')) {
                    return 'invalid email';
                  }
                  return null;
                },
                onChanged: (value) => changedValue = value,
              ),
            ),
          ),
        ),
      );

      final simulator = TextInputSimulator(WidgetFinder());
      await simulator.enterText(
        const KeyMatcher('email_field'),
        'invalid-email',
        configuration,
      );
      await tester.pump();

      expect(changedValue, 'invalid-email');
      expect(find.text('invalid email'), findsOneWidget);

      await simulator.enterText(
        const KeyMatcher('email_field'),
        'valid@example.com',
        configuration,
      );
      await tester.pump();

      expect(changedValue, 'valid@example.com');
      expect(find.text('invalid email'), findsNothing);
    });

    testWidgets('applies input formatters before onChanged by key', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'seed-bio');
      String changedValue = '';

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextFormField(
              key: const ValueKey('bio_field'),
              controller: controller,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]')),
                LengthLimitingTextInputFormatter(5),
              ],
              onChanged: (value) => changedValue = value,
            ),
          ),
        ),
      );

      final simulator = TextInputSimulator(WidgetFinder());
      await simulator.enterText(
        const KeyMatcher('bio_field'),
        'Hello!!!123',
        configuration,
      );
      await tester.pump();

      expect(changedValue, 'Hello');
    });

    testWidgets('does not mutate read-only fields by key',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: 'Locked');
      String changedValue = '';

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey('readonly_field'),
              controller: controller,
              readOnly: true,
              onChanged: (value) => changedValue = value,
            ),
          ),
        ),
      );

      final simulator = TextInputSimulator(WidgetFinder());
      await simulator.enterText(
        const KeyMatcher('readonly_field'),
        'New Value',
        configuration,
      );
      await tester.pump();

      expect(controller.text, 'Locked');
      expect(changedValue, isEmpty);
    });

    testWidgets('can match text field by existing text value', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'name-start');
      String changedValue = '';

      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey('text_field'),
              controller: controller,
              onChanged: (value) => changedValue = value,
            ),
          ),
        ),
      );

      final simulator = TextInputSimulator(WidgetFinder());
      await simulator.enterText(
        const KeyMatcher('text_field'),
        'Matched by text',
        configuration,
      );
      await tester.pump();

      expect(changedValue, 'Matched by text');
      expect(controller.text, 'Matched by text');
    });

    group('Alternative approaches for focused element input', () {
      testWidgets('supports tap then key-based text entry flow', (
        WidgetTester tester,
      ) async {
        final controller = TextEditingController(text: 'initial');

        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                key: const ValueKey('text_field'),
                controller: controller,
                decoration: const InputDecoration(hintText: 'Enter text here'),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('text_field')));
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await simulator.enterText(
          const KeyMatcher('text_field'),
          'Typed using key',
          configuration,
        );
        await tester.pump();

        expect(controller.text, 'Typed using key');
      });

      testWidgets('supports tap then key-based text entry flow', (
        WidgetTester tester,
      ) async {
        final controller = TextEditingController(text: 'seed');

        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                key: const ValueKey('tap_field'),
                controller: controller,
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('tap_field')));
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await simulator.enterText(
          const KeyMatcher('tap_field'),
          'Typed after tap',
          configuration,
        );
        await tester.pump();

        expect(controller.text, 'Typed after tap');
      });
    });
  });
}
