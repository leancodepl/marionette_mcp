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
