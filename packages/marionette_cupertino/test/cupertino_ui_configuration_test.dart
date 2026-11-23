import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_cupertino/marionette_cupertino.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

final _configuration = const MarionetteConfiguration().withCupertinoUi();

/// Lists elements the way `marionette.interactiveElements` does.
List<Map<String, dynamic>> _list(
  MarionetteConfiguration configuration, {
  List<String>? ancestorKeys,
}) {
  return findScopedInteractiveElements(
    {if (ancestorKeys != null) 'ancestor_keys': jsonEncode(ancestorKeys)},
    elementTreeFinder: ElementTreeFinder(configuration),
    widgetFinder: WidgetFinder(),
    configuration: configuration,
  );
}

Map<String, dynamic> _entry(List<Map<String, dynamic>> elements, String type) {
  return elements.singleWhere((e) => e['type'] == type);
}

bool _hasText(List<Map<String, dynamic>> elements, String text) {
  return elements.any((e) => e['text'] == text);
}

Widget _app(List<Widget> children) {
  return CupertinoApp(
    home: CupertinoPageScaffold(
      child: SafeArea(child: Column(children: children)),
    ),
  );
}

void main() {
  testWidgets(
    'lists Cupertino controls with field value and placeholder apart',
    (tester) async {
      final controller = TextEditingController(text: 'query');
      addTearDown(controller.dispose);
      final searchController = TextEditingController(text: 'q');
      addTearDown(searchController.dispose);
      await tester.pumpWidget(
        _app([
          CupertinoButton(onPressed: () {}, child: const Text('Save')),
          CupertinoTextField(controller: controller, placeholder: 'Search'),
          CupertinoSearchTextField(
            controller: searchController,
            placeholder: 'Find',
          ),
          CupertinoSlider(value: 0.5, onChanged: (_) {}),
          CupertinoSegmentedControl<int>(
            children: const {1: Text('Day'), 2: Text('Week')},
            groupValue: 1,
            onValueChanged: (_) {},
          ),
          CupertinoSlidingSegmentedControl<int>(
            children: const {1: Text('List'), 2: Text('Grid')},
            groupValue: 1,
            onValueChanged: (_) {},
          ),
        ]),
      );

      final elements = _list(_configuration);

      expect(_entry(elements, 'CupertinoButton')['text'], 'Save');
      final field = _entry(elements, 'CupertinoTextField');
      expect(field['text'], 'query');
      expect(field['label'], 'Search');
      final search = _entry(elements, 'CupertinoSearchTextField');
      expect(search['text'], 'q');
      expect(search['label'], 'Find');
      expect(_entry(elements, 'CupertinoSlider')['value'], '0.5');
      expect(_entry(elements, 'CupertinoSegmentedControl<int>'), isNotNull);
      expect(
        _entry(elements, 'CupertinoSlidingSegmentedControl<int>'),
        isNotNull,
      );
      for (final segment in ['Day', 'Week', 'List', 'Grid']) {
        expect(_hasText(elements, segment), isTrue, reason: segment);
      }
    },
  );

  testWidgets('labels a search field with its default placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_app([const CupertinoSearchTextField()]));

    final search = _entry(_list(_configuration), 'CupertinoSearchTextField');

    expect(search['text'], '');
    expect(search['label'], 'Search');
  });

  testWidgets('keeps the app configuration and composes once', (tester) async {
    await tester.pumpWidget(
      _app([const CupertinoTextField(placeholder: 'Search')]),
    );
    final configuration = MarionetteConfiguration(
      compaction: CompactionMode.none,
      extractFieldLabel: (element) =>
          element.widget is CupertinoTextField ? 'Query' : null,
    ).withCupertinoUi();

    final field = tester.element(find.byType(CupertinoTextField));
    expect(configuration.withCupertinoUi(), same(configuration));
    expect(configuration.compaction, CompactionMode.none);
    expect(configuration.fieldLabelFor(field), 'Query');
    expect(
      configuration.controlKindFor(field),
      MarionetteControlKind.textField,
    );
  });

  testWidgets(
    'enters text into the controllerless field its ancestor key scopes',
    (tester) async {
      final entered = <String, String>{};
      Widget form(String key, String placeholder) {
        return Column(
          key: ValueKey(key),
          children: [
            CupertinoTextField(
              key: const ValueKey('email'),
              placeholder: placeholder,
              onChanged: (value) => entered[key] = value,
            ),
          ],
        );
      }

      await tester.pumpWidget(
        _app([form('form_a', 'Email A'), form('form_b', 'Email B')]),
      );

      final scoped = _list(_configuration, ancestorKeys: ['form_b']);
      expect(_entry(scoped, 'CupertinoTextField')['label'], 'Email B');

      await TextInputSimulator(WidgetFinder()).enterText(
        const KeyMatcher('email'),
        'b@example.com',
        _configuration,
        ancestors: const [KeyMatcher('form_b')],
      );
      await tester.pump();
      expect(entered, {'form_b': 'b@example.com'});
      final typed = _list(_configuration, ancestorKeys: ['form_b']);
      expect(_entry(typed, 'CupertinoTextField')['text'], 'b@example.com');
      final untouched = _list(_configuration, ancestorKeys: ['form_a']);
      expect(_entry(untouched, 'CupertinoTextField')['text'], '');
    },
  );
}
