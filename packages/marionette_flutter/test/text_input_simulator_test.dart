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
              controller: controller,
              onChanged: (value) => changedValue = value,
            ),
          ),
        ),
      );

      final simulator = TextInputSimulator(WidgetFinder());
      await simulator.enterText(
        const TextMatcher('name-start'),
        'Matched by text',
        configuration,
      );
      await tester.pump();

      expect(changedValue, 'Matched by text');
      expect(controller.text, 'Matched by text');
    });

    group('FocusedElementMatcher', () {
      testWidgets('enters text into focused TextField',
          (WidgetTester tester) async {
        final controller = TextEditingController(text: 'seed');
        final focusNode = FocusNode();
        String changedValue = '';

        addTearDown(() {
          controller.dispose();
          focusNode.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: (value) => changedValue = value,
              ),
            ),
          ),
        );

        focusNode.requestFocus();
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await simulator.enterText(
          const FocusedElementMatcher(),
          'Hello Focus',
          configuration,
        );
        await tester.pump();

        expect(changedValue, 'Hello Focus');
        expect(controller.text, 'Hello Focus');
      });

      testWidgets(
          'enters text into focused TextFormField and updates validator', (
        WidgetTester tester,
      ) async {
        final controller = TextEditingController(text: 'seed-email');
        final focusNode = FocusNode();

        addTearDown(() {
          controller.dispose();
          focusNode.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                autovalidateMode: AutovalidateMode.always,
                child: TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  validator: (value) {
                    if (value == null || !value.contains('@')) {
                      return 'invalid email';
                    }
                    return null;
                  },
                ),
              ),
            ),
          ),
        );

        focusNode.requestFocus();
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await simulator.enterText(
          const FocusedElementMatcher(),
          'invalid-email',
          configuration,
        );
        await tester.pump();

        expect(find.text('invalid email'), findsOneWidget);

        await simulator.enterText(
          const FocusedElementMatcher(),
          'valid@example.com',
          configuration,
        );
        await tester.pump();

        expect(controller.text, 'valid@example.com');
        expect(find.text('invalid email'), findsNothing);
      });

      testWidgets('throws when no element is focused',
          (WidgetTester tester) async {
        final controller = TextEditingController(text: 'seed');

        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(controller: controller),
            ),
          ),
        );

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await expectLater(
          simulator.enterText(
            const FocusedElementMatcher(),
            'Should fail',
            configuration,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('No element is currently focused'),
            ),
          ),
        );
      });

      testWidgets('throws when focused element is not a text field', (
        WidgetTester tester,
      ) async {
        final focusNode = FocusNode();

        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Focus(
                focusNode: focusNode,
                child: const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        );

        focusNode.requestFocus();
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await expectLater(
          simulator.enterText(
            const FocusedElementMatcher(),
            'Should fail',
            configuration,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Focused element is not a text field'),
            ),
          ),
        );
      });

      testWidgets('supports tap then focused-element text entry flow', (
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
          const FocusedElementMatcher(),
          'Typed after tap',
          configuration,
        );
        await tester.pump();

        expect(controller.text, 'Typed after tap');
      });

      testWidgets('does not mutate read-only focused field', (
        WidgetTester tester,
      ) async {
        final controller = TextEditingController(text: 'Locked');
        final focusNode = FocusNode();

        addTearDown(() {
          controller.dispose();
          focusNode.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: true,
              ),
            ),
          ),
        );

        focusNode.requestFocus();
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await simulator.enterText(
          const FocusedElementMatcher(),
          'New Value',
          configuration,
        );
        await tester.pump();

        expect(controller.text, 'Locked');
      });

      testWidgets(
          'enters text into the currently focused field when multiple fields exist',
          (
        WidgetTester tester,
      ) async {
        final firstController = TextEditingController(text: 'first-seed');
        final secondController = TextEditingController(text: 'second-seed');
        final firstFocusNode = FocusNode();
        final secondFocusNode = FocusNode();

        addTearDown(() {
          firstController.dispose();
          secondController.dispose();
          firstFocusNode.dispose();
          secondFocusNode.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(
                    controller: firstController,
                    focusNode: firstFocusNode,
                  ),
                  TextField(
                    controller: secondController,
                    focusNode: secondFocusNode,
                  ),
                ],
              ),
            ),
          ),
        );

        secondFocusNode.requestFocus();
        await tester.pump();

        final simulator = TextInputSimulator(WidgetFinder());
        await simulator.enterText(
          const FocusedElementMatcher(),
          'updated-second',
          configuration,
        );
        await tester.pump();

        expect(firstController.text, 'first-seed');
        expect(secondController.text, 'updated-second');
      });
    });
  });
}
