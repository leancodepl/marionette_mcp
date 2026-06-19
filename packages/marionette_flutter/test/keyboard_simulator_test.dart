import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/keyboard_simulator.dart';

const _timeout = Timeout(Duration(seconds: 10));

void main() {
  group('KeyboardSimulator.pressKey', () {
    testWidgets(
      'dispatches a matched down/up pair for a named key to the focused widget',
      timeout: _timeout,
      (WidgetTester tester) async {
        final events = <KeyEvent>[];
        await tester.pumpWidget(_focusHarness(events.add));
        await tester.pump();

        await KeyboardSimulator().pressKey('enter');
        await tester.pump();

        final down = events.whereType<KeyDownEvent>().toList();
        final up = events.whereType<KeyUpEvent>().toList();
        expect(down, hasLength(1));
        expect(up, hasLength(1));
        expect(down.single.logicalKey, LogicalKeyboardKey.enter);
        expect(up.single.logicalKey, LogicalKeyboardKey.enter);
        // Enter is non-printable: no character delivered.
        expect(down.single.character, isNull);
      },
    );

    testWidgets(
      'delivers a character for an unmodified printable key',
      timeout: _timeout,
      (WidgetTester tester) async {
        final events = <KeyEvent>[];
        await tester.pumpWidget(_focusHarness(events.add));
        await tester.pump();

        await KeyboardSimulator().pressKey('a');
        await tester.pump();

        final down = events.whereType<KeyDownEvent>().single;
        expect(down.logicalKey, LogicalKeyboardKey.keyA);
        expect(down.character, 'a');
      },
    );

    testWidgets(
      'uppercases the character when shift is held',
      timeout: _timeout,
      (WidgetTester tester) async {
        final events = <KeyEvent>[];
        await tester.pumpWidget(_focusHarness(events.add));
        await tester.pump();

        await KeyboardSimulator().pressKey('a', modifiers: {'shift'});
        await tester.pump();

        final letterDown = events
            .whereType<KeyDownEvent>()
            .firstWhere((e) => e.logicalKey == LogicalKeyboardKey.keyA);
        expect(letterDown.character, 'A');
      },
    );

    testWidgets(
      'holds modifiers so Shortcuts activate, and suppresses the character',
      timeout: _timeout,
      (WidgetTester tester) async {
        final events = <KeyEvent>[];
        var selectAllCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyA, control: true):
                    () => selectAllCount++,
              },
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  events.add(event);
                  return KeyEventResult.ignored;
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pump();

        await KeyboardSimulator().pressKey('a', modifiers: {'control'});
        await tester.pump();

        expect(selectAllCount, 1, reason: 'control+a should fire the shortcut');

        // Control wraps the letter: control down, a down, a up, control up.
        final logicalDownOrder = events
            .whereType<KeyDownEvent>()
            .map((e) => e.logicalKey)
            .toList();
        expect(logicalDownOrder, [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.keyA,
        ]);
        // The control modifier suppresses the typed character.
        final letterDown = events
            .whereType<KeyDownEvent>()
            .firstWhere((e) => e.logicalKey == LogicalKeyboardKey.keyA);
        expect(letterDown.character, isNull);

        // The keyboard must not be left with any key held.
        expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
      },
    );

    testWidgets(
      'throws ArgumentError for an unknown key',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(_focusHarness((_) {}));
        await tester.pump();

        expect(
          () => KeyboardSimulator().pressKey('nope'),
          throwsArgumentError,
        );
      },
    );

    testWidgets(
      'throws ArgumentError for an unknown modifier',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(_focusHarness((_) {}));
        await tester.pump();

        expect(
          () => KeyboardSimulator().pressKey('a', modifiers: {'hyper'}),
          throwsArgumentError,
        );
      },
    );
  });
}

/// A minimal app with an autofocused [Focus] that reports every [KeyEvent] it
/// receives to [onKeyEvent].
Widget _focusHarness(void Function(KeyEvent) onKeyEvent) {
  return MaterialApp(
    home: Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        onKeyEvent(event);
        return KeyEventResult.ignored;
      },
      child: const SizedBox.expand(),
    ),
  );
}
