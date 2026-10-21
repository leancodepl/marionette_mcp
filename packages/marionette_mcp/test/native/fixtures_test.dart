// L3 tests: parsers, selector and unit conversion on UI trees captured from
// real devices with tool/capture_native_fixture.dart.
import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:test/test.dart';

/// A captured fixture: elements in screenshot pixels plus metadata.
final class Fixture {
  Fixture(this.platform, this.name) {
    final base = 'test/native/fixtures/$platform/$name';
    xml = File('$base.xml').readAsStringSync();
    final meta = jsonDecode(File('$base.json').readAsStringSync())
        as Map<String, dynamic>;
    final screenJson = meta['screen'] as Map<String, dynamic>;
    screen = NativeScreen(
      width: screenJson['width'] as int,
      height: screenJson['height'] as int,
      scale: (screenJson['scale'] as num).toDouble(),
    );
    foregroundApp = meta['foregroundApp'] as String?;
    final parsed =
        platform == 'android' ? parseAndroidUiDump(xml) : parseWdaSource(xml);
    // Same conversion as WebDriverNativeConnector.getNativeElements.
    elements = [for (final e in parsed) e.scaled(screen.scale)];
  }

  final String platform;
  final String name;
  late final String xml;
  late final NativeScreen screen;
  late final String? foregroundApp;
  late final List<NativeElement> elements;

  NativeElement select(NativeSelector selector) =>
      selectElement(elements, selector);
}

Matcher _ambiguousWith(int count) => throwsA(
      isA<NativeAmbiguousElementException>()
          .having((e) => e.message, 'message', contains('$count native')),
    );

void main() {
  group('Android 9 (API 28) fixtures', () {
    test('home: multi-line tab labels are decoded and selectable', () {
      final home = Fixture('android', 'android28_home');

      expect(
        home
            .select(const NativeSelector(text: 'Testing\nTab 3 of 4'))
            .clickable,
        isTrue,
      );
      expect(
        home
            .select(
                const NativeSelector(textContains: 'testing', type: 'Button'))
            .text,
        'Testing\nTab 3 of 4',
      );
    });

    test('permission screen: two "Request" buttons are ambiguous', () {
      final screen = Fixture('android', 'android28_permission_screen');

      expect(
        () => screen.select(const NativeSelector(text: 'Request')),
        _ambiguousWith(2),
      );
      final camera =
          screen.select(const NativeSelector(text: 'Request', index: 0));
      final photos =
          screen.select(const NativeSelector(text: 'Request', index: 1));
      expect(photos.bounds.y, greaterThan(camera.bounds.y));
    });

    test('native controls: platform-view widgets are visible natively', () {
      final controls = Fixture('android', 'android28_native_controls');

      expect(
        controls
            .select(const NativeSelector(text: 'Tap me (native)'))
            .className,
        'android.widget.Button',
      );
      expect(
        controls.select(const NativeSelector(type: 'EditText')).text,
        'Type here (native)',
      );
    });

    test('keyboard: Flutter fields are found by hint, the IME is invisible',
        () {
      final keyboard = Fixture('android', 'android28_keyboard');

      // Focused, the field's description becomes label + helper text; the
      // not-found hint points the agent to it.
      expect(
        () => keyboard.select(const NativeSelector(text: 'Amount')),
        throwsA(
          isA<NativeElementNotFoundException>().having(
              (e) => e.hint, 'hint', contains(r'"Amount\nDigits only"')),
        ),
      );
      final amount = keyboard.select(
        const NativeSelector(textContains: 'amount', type: 'EditText'),
      );
      expect(amount.text, 'Amount\nDigits only');
      expect(
        () => keyboard.select(const NativeSelector(type: 'EditText')),
        _ambiguousWith(3),
      );
      // Gboard does not publish its keys to accessibility.
      expect(keyboard.xml, isNot(contains('inputmethod')));
    });

    test('every element lies within the screen', () {
      for (final name in [
        'android28_home',
        'android28_keyboard',
        'android28_native_controls',
        'android28_permission_screen',
      ]) {
        final fixture = Fixture('android', name);
        for (final element in fixture.elements) {
          final b = element.bounds;
          expect(
            b.x >= 0 &&
                b.y >= 0 &&
                b.x + b.width <= fixture.screen.width &&
                b.y + b.height <= fixture.screen.height,
            isTrue,
            reason: '$name: ${element.toJson()}',
          );
        }
      }
    });
  });

  group('iOS 26.4 fixtures (points converted to screenshot pixels)', () {
    test('the application spans exactly the screenshot', () {
      for (final name in [
        'ios26_home',
        'ios26_keyboard',
        'ios26_native_controls',
        'ios26_permission_screen',
      ]) {
        final fixture = Fixture('ios', name);
        final app = fixture.elements.firstWhere(
          (e) => e.className == 'XCUIElementTypeApplication',
        );

        expect(app.bounds.width, fixture.screen.width, reason: name);
        expect(app.bounds.height, fixture.screen.height, reason: name);
      }
    });

    test('native controls: the button wins over its own label', () {
      final controls = Fixture('ios', 'ios26_native_controls');

      expect(
        controls
            .select(const NativeSelector(text: 'Tap me (native)'))
            .className,
        'XCUIElementTypeButton',
      );
      expect(
        controls.select(const NativeSelector(id: 'native_input')).className,
        'XCUIElementTypeTextField',
      );
    });

    test('permission screen: "Request" buttons share text and id', () {
      final screen = Fixture('ios', 'ios26_permission_screen');

      expect(
        () => screen.select(const NativeSelector(id: 'Request')),
        _ambiguousWith(2),
      );
      expect(
        screen.select(const NativeSelector(id: 'Request', index: 1)).bounds.y,
        greaterThan(
          screen.select(const NativeSelector(id: 'Request', index: 0)).bounds.y,
        ),
      );
    });

    test('keyboard keys are visible and tappable', () {
      final keyboard = Fixture('ios', 'ios26_keyboard');

      final key = keyboard.select(const NativeSelector(text: 'Q', type: 'Key'));
      expect(key.clickable, isTrue);
      expect(
        key.bounds.y,
        greaterThan(keyboard.screen.height ~/ 2),
        reason: 'the keyboard is at the bottom of the screen',
      );
    });
  });

  group('element state on captured trees', () {
    test('Android 9: the focused field, the selected tab, a scroll view', () {
      final keyboard = Fixture('android', 'android28_keyboard');
      final fields = keyboard.elements
          .where((e) => e.className == 'android.widget.EditText')
          .toList();

      expect(fields.where((e) => e.focused == true), hasLength(1));
      expect(fields.map((e) => e.value), everyElement(isNull),
          reason: 'empty fields show their hint, not a value');
      expect(keyboard.elements.where((e) => e.scrollable), isNotEmpty);

      final home = Fixture('android', 'android28_home');
      expect(home.elements.where((e) => e.selected), hasLength(1));
    });

    test('iOS 26: placeholder and tab state are not reported as value', () {
      final keyboard = Fixture('ios', 'ios26_keyboard');

      final field = keyboard.select(const NativeSelector(id: 'native_input'));
      expect(field.value, isNull);
      expect(field.text, 'Type here (native)');

      final tab = keyboard.select(const NativeSelector(textContains: 'Tab 3'));
      expect((tab.selected, tab.value), (true, null));
      expect(keyboard.elements.map((e) => e.value), everyElement(isNull));
    });
  });
}
