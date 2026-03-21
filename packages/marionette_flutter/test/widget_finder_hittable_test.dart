import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _configuration = MarionetteConfiguration();

void main() {
  group('WidgetFinder.findHittableElement', () {
    testWidgets('returns element when it is hittable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('btn'),
                onPressed: () {},
                child: const Text('Tap me'),
              ),
            ),
          ),
        ),
      );

      final finder = WidgetFinder();
      final element = finder.findHittableElement(
        const KeyMatcher('btn'),
        _configuration,
      );

      expect(element, isNotNull);
      expect(element!.widget.key, const ValueKey('btn'));
    });

    testWidgets('rejects element behind IgnorePointer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IgnorePointer(
              child: Center(
                child: ElevatedButton(
                  key: const ValueKey('ignored_btn'),
                  onPressed: () {},
                  child: const Text('Cannot tap'),
                ),
              ),
            ),
          ),
        ),
      );

      final finder = WidgetFinder();

      final hittable = finder.findHittableElement(
        const KeyMatcher('ignored_btn'),
        _configuration,
      );
      expect(hittable, isNull,
          reason: 'should not find element behind IgnorePointer');

      final plain = finder.findElement(
        const KeyMatcher('ignored_btn'),
        _configuration,
      );
      expect(plain, isNotNull, reason: 'findElement should still find it');
    });

    testWidgets('rejects element behind AbsorbPointer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AbsorbPointer(
              child: Center(
                child: ElevatedButton(
                  key: const ValueKey('absorbed_btn'),
                  onPressed: () {},
                  child: const Text('Cannot tap'),
                ),
              ),
            ),
          ),
        ),
      );

      final finder = WidgetFinder();

      final hittable = finder.findHittableElement(
        const KeyMatcher('absorbed_btn'),
        _configuration,
      );
      expect(hittable, isNull,
          reason: 'should not find element behind AbsorbPointer');

      final plain = finder.findElement(
        const KeyMatcher('absorbed_btn'),
        _configuration,
      );
      expect(plain, isNotNull, reason: 'findElement should still find it');
    });

    testWidgets('rejects element behind modal barrier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('behind_modal'),
                onPressed: () {
                  showDialog<void>(
                    context: tester.element(find.byType(ElevatedButton)),
                    builder: (_) => const AlertDialog(
                      content: Text('Dialog content'),
                    ),
                  );
                },
                child: const Text('Open dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('behind_modal')));
      await tester.pumpAndSettle();

      final finder = WidgetFinder();

      final hittable = finder.findHittableElement(
        const KeyMatcher('behind_modal'),
        _configuration,
      );
      expect(hittable, isNull,
          reason: 'should not find element behind modal barrier');

      final plain = finder.findElement(
        const KeyMatcher('behind_modal'),
        _configuration,
      );
      expect(plain, isNotNull, reason: 'findElement should still find it');
    });

    testWidgets(
      'selects front-most element when identical matcher exists behind modal barrier',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          content: ElevatedButton(
                            key: const ValueKey('dup_btn'),
                            onPressed: () {},
                            child: const Text('Dialog button'),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
                floatingActionButton: ElevatedButton(
                  key: const ValueKey('dup_btn'),
                  onPressed: () {},
                  child: const Text('Background button'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final finder = WidgetFinder();
        final hittable = finder.findHittableElement(
          const KeyMatcher('dup_btn'),
          _configuration,
        );

        expect(hittable, isNotNull);

        final text = finder.findElementFrom(
          const TextMatcher('Dialog button'),
          hittable,
          _configuration,
        );
        expect(
          text,
          isNotNull,
          reason: 'should select the button inside the dialog, not behind it',
        );
      },
    );

    testWidgets(
      'GestureDispatcher.tap throws when element is behind modal barrier',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      key: const ValueKey('open_dialog'),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => const AlertDialog(
                            content: Text('Blocking dialog'),
                          ),
                        );
                      },
                      child: const Text('Open dialog'),
                    ),
                    ElevatedButton(
                      key: const ValueKey('blocked_btn'),
                      onPressed: () {},
                      child: const Text('Blocked'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('open_dialog')));
        await tester.pumpAndSettle();

        final finder = WidgetFinder();
        final element = finder.findHittableElement(
          const KeyMatcher('blocked_btn'),
          _configuration,
        );

        expect(
          element,
          isNull,
          reason: 'tap tool should not silently target a blocked element',
        );
      },
    );
  });

  group('extractText with Element access', () {
    testWidgets(
      'custom extractText can walk element tree to find TextField label',
      (tester) async {
        final configuration = MarionetteConfiguration(
          extractText: (element) {
            final widget = element.widget;
            if (widget is! TextField) return null;

            // Walk the element subtree to find rendered label text
            String? labelText;
            void visitor(Element child) {
              if (labelText != null) return;
              if (child.widget is Text) {
                labelText = (child.widget as Text).data;
              } else {
                child.visitChildren(visitor);
              }
            }

            element.visitChildren(visitor);
            return labelText;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                key: const ValueKey('email_field'),
                decoration: InputDecoration(label: Text('Email')),
              ),
            ),
          ),
        );

        final finder = WidgetFinder();
        final element = finder.findElement(
          const TextMatcher('Email'),
          configuration,
        );

        expect(element, isNotNull);
        expect(element!.widget, isA<TextField>());
        expect(element.widget.key, const ValueKey('email_field'));
      },
    );
  });
}
