import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show AttributedString;
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

import 'multi_view_test_helpers.dart';

const _configuration = MarionetteConfiguration();
const _finder = ElementTreeFinder(_configuration);
const _tileFinder = ElementTreeFinder(
  MarionetteConfiguration(
    isInteractiveElement: _isTile,
    shouldStopTraversalAtElement: _isTile,
  ),
);

bool _isTile(Element element) => element.widget is _DsTile;

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

    testWidgets('Semantics joins an attributed label with its value',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              attributedLabel: AttributedString('Volume'),
              value: '70%',
              child: Container(width: 100, height: 100, color: Colors.blue),
            ),
          ),
        ),
      );

      expect(
        _finder
            .findInteractiveElements()
            .where((e) => e['type'] == 'Semantics')
            .single['text'],
        'Volume: 70%',
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

  group('ElementTreeFinder labels of controls that stop traversal', () {
    testWidgets('a control reports the label its children show as text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {},
              icon: const Icon(Icons.edit),
              label: const Text('Compose'),
            ),
            body: ListView(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Save')),
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
                SwitchListTile(
                  value: false,
                  onChanged: (_) {},
                  title: const Text('Dark mode'),
                ),
              ],
            ),
          ),
        ),
      );

      final elements = _finder.findInteractiveElements();
      // ElevatedButton.icon builds a private subclass on older Flutter.
      Object? textOf(String type) => elements
          .singleWhere((e) => (e['type'] as String).contains(type))['text'];

      expect(elements, hasLength(5));
      expect(textOf('FilledButton'), 'Save');
      expect(textOf('TextButton'), 'Cancel');
      expect(textOf('ElevatedButton'), 'Add');
      expect(textOf('SwitchListTile'), 'Dark mode');
      expect(textOf('FloatingActionButton'), 'Compose');
    });

    testWidgets('several labels are joined line by line', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckboxListTile(
              value: true,
              onChanged: (_) {},
              title: const Text('Accept terms'),
              subtitle: const Text('Required'),
            ),
          ),
        ),
      );

      expect(
        _finder.findInteractiveElements().single['text'],
        'Accept terms\nRequired',
      );
    });

    testWidgets('the reported label finds the button with tap(text:)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Save')),
          ),
        ),
      );

      final label = _finder.findInteractiveElements().single['text'] as String;
      final match = WidgetFinder().findHittableElement(
        TextMatcher(label),
        _configuration,
      );

      expect(match, isNotNull);
      var insideButton = false;
      match!.visitAncestorElements((ancestor) {
        insideButton = ancestor.widget is FilledButton;
        return !insideButton;
      });
      expect(insideButton, isTrue);
    });

    testWidgets(
        'merged, semantic-only and WidgetSpan labels do not match tap(text:)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add, semanticLabel: 'New invoice'),
            ),
            body: Column(
              children: [
                CheckboxListTile(
                  value: true,
                  onChanged: (_) {},
                  title: const Text('Accept terms'),
                  subtitle: const Text('Required'),
                ),
                FilledButton(
                  onPressed: () {},
                  child: const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Hi '),
                        WidgetSpan(child: Text('Bob')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      Element? matchText(String text) =>
          WidgetFinder().findHittableElement(TextMatcher(text), _configuration);
      final labels =
          _finder.findInteractiveElements().map((e) => e['text']).toList();

      expect(
        labels,
        containsAll(['Accept terms\nRequired', 'New invoice', 'Hi Bob']),
      );
      expect(matchText('Accept terms\nRequired'), isNull);
      expect(matchText('New invoice'), isNull);
      expect(matchText('Hi Bob'), isNull);
      expect(matchText('Accept terms'), isNotNull);
    });

    testWidgets('a Text reports its visible text, not its semanticsLabel',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: const Text('ABC', semanticsLabel: 'Alphabet'),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'ABC');
    });

    testWidgets('an icon-only control reports no text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(
        _finder.findInteractiveElements().single.containsKey('text'),
        isFalse,
      );
    });

    testWidgets('an icon reports its semanticLabel, not its glyph',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add, semanticLabel: 'New invoice'),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'New invoice');
    });

    testWidgets('text hidden by ExcludeSemantics is left out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Text('•')),
                  Text('Pay'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'Pay');
    });

    testWidgets('an app control that stops traversal reports its label',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: _DsTile(enabled: true, child: Text('Archive')),
          ),
        ),
      );

      final elements = _tileFinder.findInteractiveElements();
      expect(elements, hasLength(1));
      expect(elements.single['type'], '_DsTile');
      expect(elements.single['text'], 'Archive');
    });

    testWidgets(
        'a field without a controller does not report its label as text',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(decoration: InputDecoration(labelText: 'Email')),
          ),
        ),
      );

      final field = _finder
          .findInteractiveElements()
          .singleWhere((e) => e['type'] == 'TextField');
      expect(field['text'], '');
      expect(field['label'], 'Email');
    });

    testWidgets(
        'an app control wrapping a field with a controller reports '
        'no label as text', (tester) async {
      final controller = TextEditingController(text: 'ana@example.com');
      addTearDown(controller.dispose);
      bool isField(Element element) => element.widget is _DsField;
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          isInteractiveElement: isField,
          shouldStopTraversalAtElement: isField,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DsField(label: 'Email', controller: controller),
          ),
        ),
      );

      expect(
          finder.findInteractiveElements().single.containsKey('text'), isFalse);
    });

    testWidgets('text in an offstage subtree is left out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Offstage(child: Text('Old')), Text('Save')],
              ),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'Save');
    });

    testWidgets('only the shown child of an IndexedStack is read',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: const IndexedStack(
                index: 1,
                children: [Text('Play'), Text('Pause')],
              ),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'Pause');
    });

    testWidgets('a field below excluded semantics gets no merged label',
        (tester) async {
      final controller = TextEditingController(text: 'ana@example.com');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DsTile(
              enabled: true,
              child: Semantics(
                label: 'Email',
                excludeSemantics: true,
                child: TextField(controller: controller),
              ),
            ),
          ),
        ),
      );

      expect(
        _tileFinder.findInteractiveElements().single.containsKey('text'),
        isFalse,
      );
    });

    testWidgets('a field inside a WidgetSpan gets no merged label',
        (tester) async {
      final controller = TextEditingController(text: 'Ana');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DsTile(
              enabled: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Name '),
                    WidgetSpan(
                      child: SizedBox(
                        width: 80,
                        child: TextField(controller: controller),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        _tileFinder.findInteractiveElements().single.containsKey('text'),
        isFalse,
      );
    });

    testWidgets('extracted text of a control holding a field wins',
        (tester) async {
      final controller = TextEditingController(text: 'ana@example.com');
      addTearDown(controller.dispose);
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          isInteractiveElement: _isTile,
          shouldStopTraversalAtElement: _isTile,
          extractText: (element) => _isTile(element) ? 'Contact' : null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _DsTile(
              enabled: true,
              child: TextField(controller: controller),
            ),
          ),
        ),
      );

      expect(finder.findInteractiveElements().single['text'], 'Contact');
    });

    for (final compaction in CompactionMode.values) {
      testWidgets(
          'WidgetSpan text and labels are read inline in order '
          '(compaction: ${compaction.name})', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FilledButton(
                onPressed: () {},
                child: const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Pay '),
                      WidgetSpan(child: Text('now')),
                      TextSpan(text: ' with '),
                      WidgetSpan(
                        child: Icon(Icons.credit_card, semanticLabel: 'card'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          _finder
              .findInteractiveElements(compaction: compaction)
              .single['text'],
          'Pay now with card',
        );
      });
    }

    testWidgets('excluded and offstage WidgetSpan content is left out',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Pay'),
                    WidgetSpan(child: ExcludeSemantics(child: Text(' •'))),
                    WidgetSpan(child: Offstage(child: Text(' old'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'Pay');
    });

    testWidgets(
        'WidgetSpan content of a Text with a semanticsLabel is read, '
        'without what the span excludes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Hi '),
                    WidgetSpan(child: Text('Bob')),
                    WidgetSpan(child: ExcludeSemantics(child: Text(' •'))),
                  ],
                ),
                semanticsLabel: 'Greeting',
              ),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'Hi Bob');
    });

    testWidgets('an attributed Semantics label replaces what it excludes',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: Semantics(
                attributedLabel: AttributedString('Archive'),
                excludeSemantics: true,
                child: const Text('Move'),
              ),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'Archive');
    });

    testWidgets('an empty attributed Semantics label adds nothing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilledButton(
              onPressed: () {},
              child: Semantics(
                attributedLabel: AttributedString(''),
                child: const Text('Move'),
              ),
            ),
          ),
        ),
      );

      expect(_finder.findInteractiveElements().single['text'], 'Move');
    });

    testWidgets('compact mode keeps a merged label and drops a glyph label',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FilledButton.icon(
                  key: const ValueKey('save'),
                  onPressed: () {},
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
                FilledButton(
                  key: const ValueKey('glyph'),
                  onPressed: () {},
                  child: const Text(''),
                ),
              ],
            ),
          ),
        ),
      );

      Object? textOf(CompactionMode compaction, String key) => _finder
          .findInteractiveElements(compaction: compaction)
          .singleWhere((e) => e['key'] == key)['text'];

      expect(textOf(CompactionMode.compact, 'save'), 'Save');
      expect(textOf(CompactionMode.compact, 'glyph'), isNull,
          reason: 'a merged label made of a glyph is unreadable');
      expect(textOf(CompactionMode.none, 'save'), 'Save');
      expect(textOf(CompactionMode.none, 'glyph'), '',
          reason: 'CompactionMode.none keeps the glyphs');
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
      expect(_types(elements), isNot(contains('Text')));
      expect(elements.single['text'], 'inside',
          reason: 'The card reports the label it shows instead');
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

    group('an app widget that stops traversal', () {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          isInteractiveElement: (element) => element.widget is _DsCard,
          shouldStopTraversalAtElement: (element) => element.widget is _DsCard,
        ),
      );

      testWidgets('reports the state of the one toggle it holds',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _DsCard<bool>(
              child: Checkbox(value: true, onChanged: (_) {}),
            ),
          ),
        ));
        final elements = finder.findInteractiveElements();

        expect(
          elements.firstWhere((e) => e['type'] == '_DsCard<bool>')['value'],
          'true',
        );
        expect(_types(elements), isNot(contains('Checkbox')));
      });

      testWidgets('lists each of two toggles it holds on its own',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _DsCard<bool>(
              child: Row(
                children: [
                  Checkbox(value: false, onChanged: (_) {}),
                  Checkbox(value: true, onChanged: (_) {}),
                ],
              ),
            ),
          ),
        ));
        final elements = finder.findInteractiveElements();

        expect(
          elements.firstWhere((e) => e['type'] == '_DsCard<bool>'),
          isNot(contains('value')),
        );
        expect(
          elements.where((e) => e['type'] == 'Checkbox').map((e) => e['value']),
          ['false', 'true'],
        );
      });

      testWidgets('keeps a value it declares and lists its toggle on its own',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _DsCard<bool>(
              value: 'weekly',
              child: Checkbox(value: true, onChanged: (_) {}),
            ),
          ),
        ));
        final elements = finder.findInteractiveElements();

        expect(
          elements.firstWhere((e) => e['type'] == '_DsCard<bool>')['value'],
          'weekly',
        );
        expect(
          elements.firstWhere((e) => e['type'] == 'Checkbox')['value'],
          'true',
        );
      });

      testWidgets(
          "reports its toggle's state when compact mode drops the icon glyph "
          'it declares as value', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _DsCard<bool>(
              value: '',
              child: Checkbox(value: true, onChanged: (_) {}),
            ),
          ),
        ));

        final compact =
            finder.findInteractiveElements(compaction: CompactionMode.compact);
        expect(
          compact.firstWhere((e) => e['type'] == '_DsCard<bool>')['value'],
          'true',
        );
        expect(compact.where((e) => e['type'] == 'Checkbox'), isEmpty);

        final verbose =
            finder.findInteractiveElements(compaction: CompactionMode.none);
        expect(
          verbose.firstWhere((e) => e['type'] == '_DsCard<bool>')['value'],
          '',
        );
        expect(
          verbose.firstWhere((e) => e['type'] == 'Checkbox')['value'],
          'true',
        );
      });

      testWidgets(
          'reports its merged label and its toggle state in both compaction '
          'modes', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _DsCard<bool>(
                  key: const ValueKey('remember'),
                  value: '\uE88A',
                  child: Row(
                    children: [
                      Checkbox(value: true, onChanged: (_) {}),
                      const Expanded(child: Text('Remember me')),
                    ],
                  ),
                ),
                _DsCard<bool>(
                  key: const ValueKey('starred'),
                  child: Row(
                    children: [
                      Checkbox(value: false, onChanged: (_) {}),
                      const Text('\uE88A'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));

        final compact =
            finder.findInteractiveElements(compaction: CompactionMode.compact);
        final verbose =
            finder.findInteractiveElements(compaction: CompactionMode.none);
        Map<String, dynamic> entry(
                List<Map<String, dynamic>> elements, String key) =>
            elements.singleWhere((e) => e['key'] == key);

        expect(entry(compact, 'remember'), containsPair('text', 'Remember me'));
        expect(entry(compact, 'remember'), containsPair('value', 'true'));
        expect(entry(compact, 'starred'), isNot(contains('text')),
            reason: 'a merged label made of a glyph is unreadable');
        expect(entry(compact, 'starred'), containsPair('value', 'false'));
        expect(_types(compact), isNot(contains('Checkbox')));

        expect(entry(verbose, 'remember'), containsPair('text', 'Remember me'));
        expect(entry(verbose, 'remember'), containsPair('value', '\uE88A'));
        expect(entry(verbose, 'starred'), containsPair('text', '\uE88A'));
        expect(entry(verbose, 'starred'), containsPair('value', 'false'));
        expect(
          verbose.where((e) => e['type'] == 'Checkbox').map((e) => e['value']),
          ['true'],
          reason: 'only the toggle whose state its owner did not take is '
              'listed on its own',
        );
      });

      testWidgets(
          'lists its toggle on its own when its declared value matches the '
          "toggle's state", (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: _DsCard<bool>(
              value: 'true',
              child: Checkbox(value: true, onChanged: (_) {}),
            ),
          ),
        ));
        final elements = finder.findInteractiveElements();

        expect(
          elements.firstWhere((e) => e['type'] == 'Checkbox')['value'],
          'true',
        );
      });
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

    testWidgets('reports a TextFormField label read off its inner TextField',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextFormField(
              decoration: const InputDecoration(labelText: 'Title'),
            ),
          ),
        ),
      );

      final field = _finder
          .findInteractiveElements()
          .firstWhere((e) => e['type'] == 'TextFormField');

      expect(field['label'], 'Title');
    });

    for (final (name, field) in [
      ('TextField', TextField()),
      ('TextFormField', TextFormField()),
    ]) {
      testWidgets('reports the typed value of a $name without a controller',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: field)),
        );
        await tester.enterText(find.byType(EditableText), 'Groceries');
        await tester.pump();

        final element = _finder
            .findInteractiveElements()
            .firstWhere((e) => e['type'] == name);

        expect(element['text'], 'Groceries',
            reason: 'the value lives only in the internal controller');
      });
    }

    testWidgets('an app extractText wins over the typed value of a field',
        (tester) async {
      final finder = ElementTreeFinder(
        MarionetteConfiguration(
          extractText: (element) =>
              element.widget is TextFormField ? 'Title' : null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TextFormField())),
      );
      await tester.enterText(find.byType(EditableText), 'Groceries');
      await tester.pump();

      final element = finder
          .findInteractiveElements()
          .firstWhere((e) => e['type'] == 'TextFormField');

      expect(element['text'], 'Title');
    });

    for (final value in [true, false, null]) {
      testWidgets('reports Checkbox value $value', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Checkbox(value: value, tristate: true, onChanged: (_) {}),
          ),
        ));
        final elements = _finder.findInteractiveElements();

        expect(
          elements.firstWhere((e) => e['type'] == 'Checkbox')['value'],
          '$value',
        );
      });
    }

    testWidgets('reports CheckboxListTile value', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CheckboxListTile(
            value: true,
            title: const Text('Brushed Teeth'),
            onChanged: (_) {},
          ),
        ),
      ));
      final elements = _finder.findInteractiveElements();

      expect(
        elements.firstWhere((e) => e['type'] == 'CheckboxListTile')['value'],
        'true',
      );
    });

    for (final value in [true, false]) {
      testWidgets('reports SwitchListTile value $value', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SwitchListTile(
              value: value,
              title: const Text('Wi-Fi'),
              onChanged: (_) {},
            ),
          ),
        ));
        final elements = _finder.findInteractiveElements();

        expect(
          elements.firstWhere((e) => e['type'] == 'SwitchListTile')['value'],
          '$value',
        );
      });
    }

    for (final (name, toggle, expected) in [
      (
        'CupertinoSwitch',
        CupertinoSwitch(value: true, onChanged: (_) {}),
        'true',
      ),
      (
        'CupertinoCheckbox',
        CupertinoCheckbox(value: null, tristate: true, onChanged: (_) {}),
        'null',
      ),
    ]) {
      testWidgets('reports $name value', (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: toggle))),
        );
        final elements = _finder.findInteractiveElements();

        expect(
          elements.firstWhere((e) => e['type'] == name)['value'],
          expected,
        );
      });
    }

    for (final groupValue in [1, 2]) {
      testWidgets(
          'reports whether a Radio is selected (groupValue $groupValue)',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Radio<int>(
              value: 1,
              // RadioGroup replaces these only in newer Flutter versions.
              // ignore: deprecated_member_use
              groupValue: groupValue,
              // ignore: deprecated_member_use
              onChanged: (_) {},
            ),
          ),
        ));
        final radio = _finder
            .findInteractiveElements()
            .firstWhere((e) => e['type'] == 'Radio<int>');

        expect(radio['selected'], '${groupValue == 1}');
        expect(radio.containsKey('value'), isFalse,
            reason: "a radio's value is its option, not its state");
      });
    }

    testWidgets('reports whether a RadioListTile and its Radio are selected',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RadioListTile<int>(
            value: 1,
            // RadioGroup replaces these only in newer Flutter versions.
            // ignore: deprecated_member_use
            groupValue: 1,
            // ignore: deprecated_member_use
            onChanged: (_) {},
            title: const Text('One'),
          ),
        ),
      ));
      final elements = _finder.findInteractiveElements();

      expect(
        elements
            .firstWhere((e) => e['type'] == 'RadioListTile<int>')['selected'],
        'true',
      );
      expect(
        elements.firstWhere((e) => e['type'] == 'Radio<int>')['selected'],
        'true',
      );
    });

    testWidgets('reports whether a CupertinoRadio is selected', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: CupertinoRadio<int>(
              value: 1,
              // RadioGroup replaces these only in newer Flutter versions.
              // ignore: deprecated_member_use
              groupValue: 2,
              // ignore: deprecated_member_use
              onChanged: (_) {},
            ),
          ),
        ),
      ));
      final elements = _finder.findInteractiveElements();

      expect(
        elements
            .firstWhere((e) => e['type'] == 'CupertinoRadio<int>')['selected'],
        'false',
      );
    });

    testWidgets('a GestureDetector does not claim the state of a toggle in it',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            // So the row's empty middle, where hittability is probed, hits.
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Row(
              children: [
                Checkbox(value: true, onChanged: (_) {}),
                const Text('Remember me'),
              ],
            ),
          ),
        ),
      ));
      final elements = _finder.findInteractiveElements();

      expect(
        elements.firstWhere((e) => e['type'] == 'GestureDetector'),
        isNot(contains('value')),
      );
      expect(
        elements.firstWhere((e) => e['type'] == 'Checkbox')['value'],
        'true',
      );
    });

    testWidgets('lists a checkbox in a text field suffix on its own',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            decoration: InputDecoration(
              suffixIcon: Checkbox(value: true, onChanged: (_) {}),
            ),
          ),
        ),
      ));
      final elements = _finder.findInteractiveElements();

      expect(
        elements.firstWhere((e) => e['type'] == 'TextField'),
        isNot(contains('value')),
      );
      expect(
        elements.firstWhere((e) => e['type'] == 'Checkbox')['value'],
        'true',
      );
    });

    testWidgets('lists a switch in a button on its own', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () {},
            child: Row(
              children: [
                const Text('Wi-Fi'),
                Switch(value: true, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      ));
      final elements = _finder.findInteractiveElements();

      expect(
        elements.firstWhere((e) => e['type'] == 'ElevatedButton'),
        isNot(contains('value')),
      );
      expect(
        elements.firstWhere((e) => e['type'] == 'Switch')['value'],
        'true',
      );
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

    testWidgets('drops icon glyphs and keeps the icon semantic label',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Icon(Icons.home),
                Icon(Icons.search, semanticLabel: 'Search'),
              ],
            ),
          ),
        ),
      );

      final verbose =
          _finder.findInteractiveElements(compaction: CompactionMode.none);
      expect(verbose.where((e) => e['type'] == 'RichText'), hasLength(2),
          reason: 'CompactionMode.none keeps the glyphs');

      final compact =
          _finder.findInteractiveElements(compaction: CompactionMode.compact);
      expect(compact.map((e) => e['text']), ['Search'],
          reason: 'a private-use glyph is unreadable and unmatchable');
    });

    testWidgets('drops an icon glyph from a kept element\'s properties',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('\uE88A', key: ValueKey('glyph')),
                Text('Home', key: ValueKey('label')),
              ],
            ),
          ),
        ),
      );

      final verbose = _finder
          .findInteractiveElements(compaction: CompactionMode.none)
          .firstWhere((e) => e['key'] == 'glyph');
      expect(verbose, containsPair('text', '\uE88A'),
          reason: 'CompactionMode.none keeps the glyph as text');
      expect(verbose, containsPair('data', '\uE88A'),
          reason: 'CompactionMode.none keeps the glyph as data');

      final compact =
          _finder.findInteractiveElements(compaction: CompactionMode.compact);
      expect(
        compact.firstWhere((e) => e['key'] == 'glyph'),
        isNot(anyOf(contains('data'), contains('text'))),
        reason: 'Text also declares its glyph as `data`',
      );
      expect(compact.firstWhere((e) => e['key'] == 'label')['text'], 'Home');
    });

    testWidgets('drops an icon glyph from a supplementary private-use plane',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Icon(Icons.onetwothree))),
        ),
      );

      final verbose =
          _finder.findInteractiveElements(compaction: CompactionMode.none);
      expect(verbose.where((e) => e['type'] == 'RichText'), hasLength(1),
          reason: 'CompactionMode.none keeps the glyph');

      final compact =
          _finder.findInteractiveElements(compaction: CompactionMode.compact);
      expect(compact.where((e) => e['type'] == 'RichText'), isEmpty,
          reason: 'U+F04B5 is one private-use code point, not two surrogates');
    });

    testWidgets('keeps text that mixes a glyph with readable words',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('\uE88A Home'))),
        ),
      );

      final compact =
          _finder.findInteractiveElements(compaction: CompactionMode.compact);
      expect(compact.map((e) => e['text']), contains('\uE88A Home'),
          reason: 'TextMatcher matches the exact text, glyph included');
    });

    testWidgets('drops a glyph at the end of the BMP private-use area only',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('\uF8FF', key: ValueKey('lastPrivateUse')),
                Text('\uF900', key: ValueKey('firstCjkCompatibility')),
              ],
            ),
          ),
        ),
      );

      final compact =
          _finder.findInteractiveElements(compaction: CompactionMode.compact);
      expect(
        compact.firstWhere((e) => e['key'] == 'lastPrivateUse'),
        isNot(anyOf(contains('data'), contains('text'))),
        reason: 'U+F8FF is the last private-use code point of the BMP',
      );
      expect(
        compact.firstWhere((e) => e['key'] == 'firstCjkCompatibility')['text'],
        '\uF900',
        reason: 'U+F900 is a CJK compatibility ideograph',
      );
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
  // CompactionMode.none so `visible` is present to assert on: the compact
  // payload omits it when the element is visible.
  final elements =
      _finder.findInteractiveElements(compaction: CompactionMode.none);
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
  const _DsCard({required this.child, this.value, super.key});

  final Widget child;
  final String? value;

  @override
  Widget build(BuildContext context) => _DsBox(child: child);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('value', value));
  }
}

class _AppButton extends ElevatedButton {
  const _AppButton() : super(onPressed: _noop, child: const Text('App'));

  static void _noop() {}
}

class _DsField extends StatelessWidget {
  const _DsField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [Text(label), TextField(controller: controller)],
    );
  }
}
