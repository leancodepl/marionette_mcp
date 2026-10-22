import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:test/test.dart';

import 'support/fake_native_connector.dart';

void main() {
  group('NativeSelector.matches', () {
    final button = nativeElement(
      type: 'android.widget.Button',
      text: 'Allow only while using the app',
      id: 'com.android.permissioncontroller:id/allow',
    );

    test('text is exact', () {
      expect(
        const NativeSelector(text: 'Allow only while using the app')
            .matches(button),
        isTrue,
      );
      expect(const NativeSelector(text: 'allow').matches(button), isFalse);
    });

    test('textContains is a case-insensitive substring', () {
      expect(
        const NativeSelector(textContains: 'WHILE USING').matches(button),
        isTrue,
      );
      expect(
          const NativeSelector(textContains: 'deny').matches(button), isFalse);
    });

    test('type matches the full or the short class name', () {
      expect(
        const NativeSelector(type: 'android.widget.Button').matches(button),
        isTrue,
      );
      expect(const NativeSelector(type: 'Button').matches(button), isTrue);
      expect(
          const NativeSelector(type: 'ImageButton').matches(button), isFalse);
      expect(
        const NativeSelector(type: 'Button')
            .matches(nativeElement(type: 'XCUIElementTypeButton')),
        isTrue,
      );
    });

    test('all criteria must match', () {
      expect(
        const NativeSelector(textContains: 'allow', type: 'TextView')
            .matches(button),
        isFalse,
      );
    });

    test('isEmpty ignores index', () {
      expect(const NativeSelector(index: 1).isEmpty, isTrue);
      expect(const NativeSelector(id: 'x').isEmpty, isFalse);
    });
  });

  group('selectElement', () {
    test('returns the single match', () {
      final ok = nativeElement(text: 'OK');

      expect(
        selectElement([nativeElement(text: 'Cancel'), ok],
            const NativeSelector(text: 'OK')),
        same(ok),
      );
    });

    test('prefers the one clickable match over labels', () {
      // iOS: "Tap me (native)" is both the Button and its StaticText.
      final label = nativeElement(
        type: 'XCUIElementTypeStaticText',
        text: 'Tap me (native)',
        clickable: false,
      );
      final button = nativeElement(
        type: 'XCUIElementTypeButton',
        text: 'Tap me (native)',
      );

      expect(
        selectElement(
          [button, label],
          const NativeSelector(text: 'Tap me (native)'),
        ),
        same(button),
      );
    });

    test('fails with candidates when several clickable elements match', () {
      // The example app's permission screen has two "Request" buttons.
      final elements = [
        nativeElement(text: 'Request', y: 100),
        nativeElement(text: 'Request', y: 200),
      ];

      expect(
        () => selectElement(elements, const NativeSelector(text: 'Request')),
        throwsA(
          isA<NativeAmbiguousElementException>()
              .having(
                  (e) => e.message, 'message', contains('2 native elements'))
              .having((e) => e.message, 'message', contains('[1]'))
              .having((e) => e.message, 'message', contains('bounds=(0, 200'))
              .having((e) => e.hint, 'hint', contains('index (0-1')),
        ),
      );
    });

    test('candidates escape line breaks in ids, as in texts', () {
      // WDA reports a Flutter tab's label as its id, e.g. "Home\nTab 1 of 4".
      final elements = [
        nativeElement(text: 'Home\nTab 1 of 4', id: 'Home\nTab 1 of 4'),
        nativeElement(text: 'Profile\nTab 2 of 4', id: 'Profile\nTab 2 of 4'),
      ];

      expect(
        () =>
            selectElement(elements, const NativeSelector(textContains: 'Tab')),
        throwsA(
          isA<NativeAmbiguousElementException>().having(
            (e) => e.message,
            'message',
            contains(r'id="Home\nTab 1 of 4" clickable'),
          ),
        ),
      );
    });

    test('fails when several non-clickable elements match', () {
      final elements = [
        nativeElement(text: 'Note', clickable: false),
        nativeElement(text: 'Note', clickable: false),
      ];

      expect(
        () => selectElement(elements, const NativeSelector(text: 'Note')),
        throwsA(isA<NativeAmbiguousElementException>()),
      );
    });

    test('index picks among all matches in tree order', () {
      final label = nativeElement(text: 'Request', clickable: false);
      final first = nativeElement(text: 'Request', y: 100);
      final second = nativeElement(text: 'Request', y: 200);
      final elements = [label, first, second];

      expect(
        selectElement(
            elements, const NativeSelector(text: 'Request', index: 2)),
        same(second),
      );
      expect(
        selectElement(
            elements, const NativeSelector(text: 'Request', index: 0)),
        same(label),
        reason: 'index is applied before the clickable preference',
      );
    });

    test('an index out of range reports the number of matches', () {
      expect(
        () => selectElement(
          [nativeElement(text: 'OK')],
          const NativeSelector(text: 'OK', index: 3),
        ),
        throwsA(
          isA<NativeElementNotFoundException>()
              .having((e) => e.message, 'message', contains('(1 match)')),
        ),
      );
    });

    test('no match lists similar texts', () {
      final elements = [
        nativeElement(text: 'Home\nTab 1 of 4'),
        nativeElement(text: 'Settings'),
        nativeElement(text: 'OK'),
      ];

      expect(
        () => selectElement(elements, const NativeSelector(text: 'home')),
        throwsA(
          isA<NativeElementNotFoundException>()
              .having((e) => e.message, 'message', contains('text="home"'))
              .having((e) => e.hint, 'hint', contains(r'"Home\nTab 1 of 4"'))
              .having((e) => e.hint, 'hint', isNot(contains('Settings')))
              .having((e) => e.hint, 'hint', isNot(contains('native_scroll'))),
        ),
      );
    });

    test('no match on a screen with a list hints to scroll', () {
      // A lazy list builds only the rows near the screen, so "Row 40" is not
      // in the tree at all — not even as an off-screen node.
      final elements = [
        nativeElement(type: 'android.widget.ScrollView', scrollable: true),
        nativeElement(text: 'Row 1'),
      ];

      expect(
        () => selectElement(elements, const NativeSelector(text: 'Row 40')),
        throwsA(
          isA<NativeElementNotFoundException>()
              .having((e) => e.hint, 'hint', contains('native_get_elements'))
              .having((e) => e.hint, 'hint', contains('native_scroll')),
        ),
      );
    });

    test('short texts are not suggested for a longer wanted text', () {
      expect(
        () => selectElement(
          [nativeElement(text: 'OK')],
          const NativeSelector(text: 'OK, got it'),
        ),
        throwsA(
          isA<NativeElementNotFoundException>()
              .having((e) => e.hint, 'hint', isNot(contains('Similar'))),
        ),
      );
    });

    test('a toast is never a target, and the error says why', () {
      final toast = nativeElement(
        type: 'android.widget.Toast',
        text: 'Saved',
        clickable: false,
        width: 0,
        height: 0,
      );

      expect(
        () => selectElement([toast], const NativeSelector(text: 'Saved')),
        throwsA(
          isA<NativeElementNotFoundException>()
              .having((e) => e.hint, 'hint', contains('toast')),
        ),
      );
    });

    test('a label also matches the first line (focused field on iOS)', () {
      final focused = nativeElement(
        type: 'XCUIElementTypeTextField',
        text: 'Title\nSingle line — keyboard shows Done',
      );

      expect(
        selectElement(
          [focused],
          const NativeSelector(text: 'Title', textMatchesFirstLine: true),
        ),
        same(focused),
      );
      expect(
        () => selectElement([focused], const NativeSelector(text: 'Title')),
        throwsA(isA<NativeElementNotFoundException>()),
        reason: 'plain text selectors stay exact',
      );
    });

    test('off-screen (zero-size) elements never match', () {
      final offScreen = nativeElement(text: 'Row 40', width: 0, height: 0);
      final onScreen = nativeElement(text: 'Row 4', y: 300);

      expect(
        selectElement(
          [offScreen, onScreen],
          const NativeSelector(textContains: 'Row 4'),
        ),
        same(onScreen),
        reason: 'not ambiguous: the off-screen row does not count',
      );
      expect(
        () => selectElement(
          [offScreen, onScreen],
          const NativeSelector(text: 'Row 40'),
        ),
        throwsA(
          isA<NativeElementNotFoundException>()
              .having((e) => e.hint, 'hint', contains('native_scroll')),
        ),
      );
    });

    test('describe renders every criterion', () {
      expect(
        const NativeSelector(
          text: 'A\nB',
          textContains: 'b',
          id: 'x',
          type: 'Button',
          index: 1,
        ).describe(),
        r'text="A\nB", textContains="b", id="x", type="Button", index=1',
      );
    });
  });
}
