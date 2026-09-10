import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';

import 'multi_view_test_helpers.dart';

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
          (e) => e['type'] == 'Semantics' && e['identifier'] == 'submit_button',
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

  group('ElementTreeFinder built-in generic widgets', () {
    Future<List<Map<String, dynamic>>> discover(
      WidgetTester tester,
      Widget child,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );
      return _finder.findInteractiveElements();
    }

    const items = [DropdownMenuItem(value: 'Apple', child: Text('Apple'))];

    testWidgets('DropdownButton is recognized and keeps its selected value',
        (tester) async {
      final elements = await discover(
        tester,
        DropdownButton<String>(
          value: 'Apple',
          items: items,
          onChanged: (_) {},
        ),
      );

      expect(_types(elements), contains('DropdownButton<String>'));
      expect(elements.any((e) => e['text'] == 'Apple'), isTrue);
    });

    testWidgets(
        'DropdownButtonFormField is recognized and keeps its selected value',
        (tester) async {
      final elements = await discover(
        tester,
        SizedBox(
          width: 300,
          child: DropdownButtonFormField<String>(
            // `initialValue` replaces it only in newer Flutter versions.
            // ignore: deprecated_member_use
            value: 'Apple',
            items: items,
            onChanged: (_) {},
          ),
        ),
      );

      expect(_types(elements), contains('DropdownButtonFormField<String>'));
      expect(elements.any((e) => e['text'] == 'Apple'), isTrue);
    });

    testWidgets('Radio is recognized and stops traversal like Checkbox',
        (tester) async {
      final elements = await discover(
        tester,
        Radio<int>(
          value: 1,
          // RadioGroup replaces these only in newer Flutter versions.
          // ignore: deprecated_member_use
          groupValue: 1,
          // ignore: deprecated_member_use
          onChanged: (_) {},
        ),
      );

      expect(_types(elements), {'Radio<int>'});
    });

    testWidgets('RadioListTile is recognized and keeps its title',
        (tester) async {
      final elements = await discover(
        tester,
        RadioListTile<int>(
          value: 1,
          // RadioGroup replaces these only in newer Flutter versions.
          // ignore: deprecated_member_use
          groupValue: 1,
          // ignore: deprecated_member_use
          onChanged: (_) {},
          title: const Text('One'),
        ),
      );

      expect(_types(elements), contains('RadioListTile<int>'));
      expect(elements.any((e) => e['text'] == 'One'), isTrue);
    });

    testWidgets('PopupMenuButton is recognized and keeps its child',
        (tester) async {
      final elements = await discover(
        tester,
        PopupMenuButton<String>(
          itemBuilder: (_) => const [],
          child: const Text('Menu'),
        ),
      );

      expect(_types(elements), contains('PopupMenuButton<String>'));
      expect(elements.any((e) => e['text'] == 'Menu'), isTrue);
    });
  });

  group('ElementTreeFinder built-in widget subclasses', () {
    testWidgets('ElevatedButton.icon is reported like a plain ElevatedButton',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Save'),
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      expect(elements, hasLength(1));
      expect(elements.single['type'], contains('ElevatedButton'));
    });

    testWidgets('an app subclass of a built-in button is recognized',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: _AppButton())),
      );

      expect(
        _types(_finder.findInteractiveElements()),
        {'_AppButton'},
      );
    });
  });

  group('ElementTreeFinder isInteractiveElement', () {
    testWidgets('matches generic widgets and subclasses with an is check',
        (tester) async {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          isInteractiveElement: (element) => switch (element.widget) {
            _DsSelect() || _DsButton() => true,
            _ => false,
          },
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _DsSelect<String>(),
                _DsSelect<int>(),
                _DsPrimaryButton(),
              ],
            ),
          ),
        ),
      );

      final types = _types(finder.findInteractiveElements());
      expect(types, contains('_DsSelect<String>'));
      expect(types, contains('_DsSelect<int>'));
      expect(types, contains('_DsPrimaryButton'));
    });

    testWidgets('can decide per instance from the widget fields',
        (tester) async {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          isInteractiveElement: (element) => switch (element.widget) {
            _DsTile(:final enabled) => enabled,
            _ => false,
          },
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _DsTile(enabled: true),
                _DsTile(enabled: false),
              ],
            ),
          ),
        ),
      );

      final tiles = finder
          .findInteractiveElements()
          .where((e) => e['type'] == '_DsTile')
          .toList();
      expect(tiles, hasLength(1));
    });

    testWidgets('is combined with the deprecated isInteractiveWidget with OR',
        (tester) async {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          // ignore: deprecated_member_use_from_same_package
          isInteractiveWidget: (type) => type == _DsTile,
          isInteractiveElement: (element) => element.widget is _DsButton,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _DsTile(enabled: true),
                _DsPrimaryButton(),
              ],
            ),
          ),
        ),
      );

      final types = _types(finder.findInteractiveElements());
      expect(types, contains('_DsTile'));
      expect(types, contains('_DsPrimaryButton'));
    });

    testWidgets('does not replace the built-in interactive widgets',
        (tester) async {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(isInteractiveElement: (_) => false),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(onPressed: () {}, child: const SizedBox()),
          ),
        ),
      );

      expect(
        _types(finder.findInteractiveElements()),
        contains('ElevatedButton'),
      );
    });
  });

  group('ElementTreeFinder shouldStopTraversalAtElement', () {
    const card = MaterialApp(
      home: Scaffold(body: _DsCard<String>(child: Text('inside'))),
    );

    testWidgets('skips the descendants of matching elements', (tester) async {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          isInteractiveElement: (element) => element.widget is _DsCard,
          shouldStopTraversalAtElement: (element) => element.widget is _DsCard,
        ),
      );

      await tester.pumpWidget(card);

      final elements = finder.findInteractiveElements();
      expect(_types(elements), contains('_DsCard<String>'),
          reason: 'The element where traversal stops is still discovered');
      expect(elements.any((e) => e['text'] == 'inside'), isFalse);
    });

    testWidgets('descends into everything when null', (tester) async {
      await tester.pumpWidget(card);

      expect(
        _finder.findInteractiveElements().any((e) => e['text'] == 'inside'),
        isTrue,
      );
    });

    testWidgets('is combined with the deprecated shouldStopTraversal with OR',
        (tester) async {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          // ignore: deprecated_member_use_from_same_package
          shouldStopTraversal: (type) => type == _DsTile,
          shouldStopTraversalAtElement: (element) => element.widget is _DsCard,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _DsCard<int>(child: Text('in card')),
                _DsTile(enabled: true, child: Text('in tile')),
                Text('outside'),
              ],
            ),
          ),
        ),
      );

      final texts =
          finder.findInteractiveElements().map((e) => e['text']).toSet();
      expect(texts, isNot(contains('in card')));
      expect(texts, isNot(contains('in tile')));
      expect(texts, contains('outside'));
    });
  });

  group('ElementTreeFinder visibility in a non-implicit view', () {
    testWidgets(
      'an element inside the view is visible even when the implicit view is '
      'smaller',
      (tester) async {
        // 1000x1000 logical at the test device pixel ratio of 3 — larger than
        // the implicit view (800x600), so an element past the implicit view's
        // width is still well inside this one.
        final fakeView = FakeView(tester.view)
          ..physicalSize = const Size(3000, 3000);

        await tester.pumpWidget(
          wrapWithView: false,
          View(
            view: fakeView,
            child: _probeAt(const Offset(850, 100)),
          ),
        );

        final probe = _findProbe();
        expect(probe['visible'], isTrue,
            reason: 'Visibility must be measured against the view the element '
                'is mounted in, not the implicit view');
      },
    );

    testWidgets(
      'an element painted past the view bounds is not visible',
      (tester) async {
        // 400x300 logical — smaller than the implicit view, so the offset
        // below is outside this view while still inside the implicit one.
        final fakeView = FakeView(tester.view)
          ..physicalSize = const Size(1200, 900);

        await tester.pumpWidget(
          wrapWithView: false,
          View(
            view: fakeView,
            child: _probeAt(const Offset(500, 0)),
          ),
        );

        final probe = _findProbe();
        expect(probe['visible'], isFalse,
            reason: 'An element painted beyond its own view is off screen '
                'even though the implicit view would be large enough');
      },
    );
  });

  group('ElementTreeFinder property filtering', () {
    testWidgets('drops object-valued properties without any flag',
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

      final button = _finder
          .findInteractiveElements(compaction: CompactionMode.none)
          .firstWhere((e) => e['type'] == 'ElevatedButton');

      expect(button.containsKey('style'), isFalse,
          reason:
              'the ButtonStyle blob is dropped even at CompactionMode.none');
      expect(button.containsKey('focusNode'), isFalse,
          reason: 'the FocusNode blob is dropped even at CompactionMode.none');
      expect(button['enabled'], 'true',
          reason: 'primitive state flags are kept');
    });

    testWidgets('recovers a keyless TextField label without any flag',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: TextEditingController(),
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ),
        ),
      );

      final field = _finder
          .findInteractiveElements(compaction: CompactionMode.none)
          .firstWhere((e) => e['type'] == 'TextField');

      expect(field.containsKey('decoration'), isFalse,
          reason: 'the InputDecoration blob is dropped even at '
              'CompactionMode.none');
      expect(field['label'], 'Email',
          reason: 'without the label an empty keyless field has no handle');
    });
  });

  group('ElementTreeFinder compact mode', () {
    testWidgets('drops rendering details that no interaction tool reads',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const Text(
                'Agenda',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textWidthBasis: TextWidthBasis.longestLine,
              ),
            ),
          ),
        ),
      );

      final elements =
          _finder.findInteractiveElements(compaction: CompactionMode.compact);
      final compact = <String, dynamic>{
        for (final element in elements) ...element,
      };

      for (final name in [
        'textAlign',
        'textDirection',
        'softWrap',
        'overflow',
        'textWidthBasis',
        'startBehavior',
      ]) {
        expect(compact.containsKey(name), isFalse,
            reason: '$name describes rendering, not anything actionable');
      }
      expect(compact['text'], 'Agenda', reason: 'the words themselves stay');
    });

    testWidgets('drops the text-style primitives Text inlines unprefixed',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Agenda',
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 20,
                  letterSpacing: 1.5,
                  height: 1.2,
                  textBaseline: TextBaseline.alphabetic,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ),
        ),
      );

      final compact = _finder
          .findInteractiveElements(compaction: CompactionMode.compact)
          .firstWhere((e) => e['type'] == 'Text');

      for (final name in [
        'inherit',
        'family',
        'size',
        'letterSpacing',
        'height',
        'baseline',
        'leadingDistribution',
      ]) {
        expect(compact.containsKey(name), isFalse,
            reason: 'Text inlines $name from its style with no prefix');
      }
      expect(compact['text'], 'Agenda');
    });

    testWidgets('reports visible only when an element is not visible',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () {}, child: const Text('Go')),
            ),
          ),
        ),
      );
      addTearDown(tester.view.reset);

      final onScreen = _finder
          .findInteractiveElements(compaction: CompactionMode.compact)
          .firstWhere((e) => e['type'] == 'ElevatedButton');
      expect(onScreen.containsKey('visible'), isFalse,
          reason: 'absence means visible, which is the ordinary case');

      // Shrink the view without pumping, so the laid-out button now sits
      // outside the screen while the render tree stays hittable.
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(4, 4);

      final offScreen = _finder
          .findInteractiveElements(compaction: CompactionMode.compact)
          .firstWhere((e) => e['type'] == 'ElevatedButton');
      expect(offScreen['visible'], isFalse,
          reason: 'the exception stays impossible to miss');
    });

    testWidgets('drops Text data when it duplicates text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('Agenda')))),
      );

      final verbose = _finder
          .findInteractiveElements(compaction: CompactionMode.none)
          .firstWhere((e) => e['type'] == 'Text');
      expect(verbose['data'], 'Agenda',
          reason: 'Text declares its string twice by default');

      final compact = _finder
          .findInteractiveElements(compaction: CompactionMode.compact)
          .firstWhere((e) => e['type'] == 'Text');
      expect(compact.containsKey('data'), isFalse);
      expect(compact['text'], 'Agenda');
    });

    testWidgets('rounds bounds to whole logical pixels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () {}, child: const Text('Go')),
            ),
          ),
        ),
      );

      final verboseBounds = _finder
              .findInteractiveElements(compaction: CompactionMode.none)
              .firstWhere((e) => e['type'] == 'ElevatedButton')['bounds']!
          as Map<String, dynamic>;
      expect(verboseBounds['x'], isA<double>(),
          reason: 'CompactionMode.none keeps the raw doubles');

      final compactBounds = _finder
              .findInteractiveElements(compaction: CompactionMode.compact)
              .firstWhere((e) => e['type'] == 'ElevatedButton')['bounds']!
          as Map<String, dynamic>;
      for (final key in ['x', 'y', 'width', 'height']) {
        expect(compactBounds[key], isA<int>(),
            reason: 'compact rounds $key to a whole logical pixel');
      }
      expect(compactBounds['x'], (verboseBounds['x']! as double).round());
    });
  });

  group('ElementTreeFinder compaction configuration', () {
    const verboseFinder = ElementTreeFinder(
      MarionetteConfiguration(compaction: CompactionMode.none),
    );

    Future<void> pumpText(WidgetTester tester) => tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('Agenda'))),
          ),
        );

    testWidgets('an app that configures nothing gets the compact payload',
        (tester) async {
      await pumpText(tester);

      final element = _finder
          .findInteractiveElements()
          .firstWhere((e) => e['type'] == 'Text');

      expect(element.containsKey('data'), isFalse,
          reason: 'CompactionMode.compact is the app default');
      expect(element.containsKey('visible'), isFalse);
    });

    testWidgets('compaction: compact overrides an app that opted out',
        (tester) async {
      await pumpText(tester);

      final element = verboseFinder
          .findInteractiveElements(compaction: CompactionMode.compact)
          .firstWhere((e) => e['type'] == 'Text');

      expect(element.containsKey('data'), isFalse);
      expect(element.containsKey('visible'), isFalse);
    });

    testWidgets('compaction: none overrides an app that kept the default',
        (tester) async {
      await pumpText(tester);

      final element = _finder
          .findInteractiveElements(compaction: CompactionMode.none)
          .firstWhere((e) => e['type'] == 'Text');

      expect(element['data'], 'Agenda',
          reason: 'an agent can still ask for the full payload');
      expect(element['visible'], isTrue);
    });
  });
}

/// A hit-testable probe placed at [offset] within its view.
///
/// [Transform.translate] moves the probe for hit testing as well as for
/// painting — the hit test is performed at the translated position — and hit
/// tests are not clipped to the view bounds, so the probe stays reachable
/// wherever it is put, including past the edge of its own view. That is what
/// makes it usable here: reachability is held constant, and the only thing
/// that varies is where the probe sits relative to its view, which is exactly
/// what the visibility check measures.
Widget _probeAt(Offset offset) {
  return Transform.translate(
    offset: offset,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 100,
        height: 100,
        child: GestureDetector(
          key: const ValueKey('probe'),
          behavior: HitTestBehavior.opaque,
          onTap: () {},
        ),
      ),
    ),
  );
}

Map<String, dynamic> _findProbe() {
  final elements = _finder.findInteractiveElements();
  return elements.firstWhere(
    (e) => e['key'] == 'probe',
    orElse: () => throw StateError(
      'The probe should be discoverable: $elements',
    ),
  );
}

Set<Object?> _types(List<Map<String, dynamic>> elements) {
  return elements.map((e) => e['type']).toSet();
}

/// A hit-testable box standing in for a design-system widget.
class _DsBox extends StatelessWidget {
  const _DsBox({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 40,
      child: ColoredBox(color: const Color(0xFF000000), child: child),
    );
  }
}

class _DsSelect<T> extends StatelessWidget {
  const _DsSelect();

  @override
  Widget build(BuildContext context) => const _DsBox();
}

abstract class _DsButton extends StatelessWidget {
  const _DsButton();

  @override
  Widget build(BuildContext context) => const _DsBox();
}

class _DsPrimaryButton extends _DsButton {
  const _DsPrimaryButton();
}

class _DsTile extends StatelessWidget {
  const _DsTile({required this.enabled, this.child});

  final bool enabled;
  final Widget? child;

  @override
  Widget build(BuildContext context) => _DsBox(child: child);
}

class _DsCard<T> extends StatelessWidget {
  const _DsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _DsBox(child: child);
}

class _AppButton extends ElevatedButton {
  const _AppButton() : super(onPressed: _noop, child: const Text('App'));

  static void _noop() {}
}
