import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_material/marionette_material.dart';
import 'package:material_ui/material_ui.dart';

final _configuration = const MarionetteConfiguration().withMaterialUi();

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

Map<String, dynamic> _keyed(List<Map<String, dynamic>> elements, String key) {
  return elements.singleWhere((e) => e['key'] == key);
}

bool _hasText(List<Map<String, dynamic>> elements, String text) {
  return elements.any((e) => e['text'] == text);
}

/// An app button class built on a `material_ui` button.
class _LinkButton extends TextButton {
  const _LinkButton({required super.onPressed, required super.child});
}

Widget _app(List<Widget> children) {
  return MaterialApp(
    home: Scaffold(body: Column(children: children)),
  );
}

void main() {
  testWidgets('lists Material actions and keeps selection text reachable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.save),
          label: const Text('Save'),
        ),
        _LinkButton(onPressed: () {}, child: const Text('Help')),
        IconButton(onPressed: () {}, icon: const Icon(Icons.delete)),
        FloatingActionButton(onPressed: () {}, child: const Text('Add')),
        InkWell(onTap: () {}, child: const Text('Open')),
        DropdownButton<String>(
          value: 'Weekly',
          items: const [
            DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
          ],
          onChanged: (_) {},
        ),
        PopupMenuButton<int>(
          itemBuilder: (_) => const [],
          child: const Text('More'),
        ),
        Slider(value: 0.5, onChanged: (_) {}),
        CheckboxListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('Remember me'),
        ),
      ]),
    );

    final elements = _list(_configuration);

    expect(_entry(elements, 'ElevatedButton')['text'], 'Save');
    expect(_entry(elements, '_LinkButton')['text'], 'Help');
    _entry(elements, 'IconButton');
    expect(_entry(elements, 'FloatingActionButton')['text'], 'Add');
    expect(elements.map((e) => e['type']), contains('InkWell'));
    _entry(elements, 'DropdownButton<String>');
    _entry(elements, 'PopupMenuButton<int>');
    expect(_entry(elements, 'Slider')['value'], '0.5');
    expect(_entry(elements, 'CheckboxListTile')['value'], 'true');
    for (final text in ['Open', 'Weekly', 'More']) {
      expect(_hasText(elements, text), isTrue, reason: text);
    }
  });

  testWidgets('lists Material fields with value and label apart', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Ada');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app([
        TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextFormField(
          initialValue: '',
          decoration: const InputDecoration(hintText: 'City'),
        ),
        DropdownButtonFormField<String>(
          initialValue: 'Small',
          items: const [DropdownMenuItem(value: 'Small', child: Text('Small'))],
          onChanged: (_) {},
        ),
      ]),
    );

    final elements = _list(_configuration);

    final field = _entry(elements, 'TextField');
    expect(field['text'], 'Ada');
    expect(field['label'], 'Name');
    final formField = _entry(elements, 'TextFormField');
    expect(formField['text'], '');
    expect(formField['label'], 'City');
    _entry(elements, 'DropdownButtonFormField<String>');
    expect(_hasText(elements, 'Small'), isTrue);
  });

  testWidgets(
    'enters text into the controllerless field its ancestor key scopes',
    (tester) async {
      final entered = <String, String>{};
      Widget form(String key, String label) {
        return Column(
          key: ValueKey(key),
          children: [
            TextField(
              key: const ValueKey('email'),
              decoration: InputDecoration(labelText: label),
              onChanged: (value) => entered[key] = value,
            ),
          ],
        );
      }

      await tester.pumpWidget(
        _app([form('form_a', 'Email A'), form('form_b', 'Email B')]),
      );

      final scoped = _list(_configuration, ancestorKeys: ['form_b']);
      expect(_entry(scoped, 'TextField')['label'], 'Email B');

      await TextInputSimulator(WidgetFinder()).enterText(
        const KeyMatcher('email'),
        'b@example.com',
        _configuration,
        ancestors: const [KeyMatcher('form_b')],
      );
      await tester.pump();
      expect(entered, {'form_b': 'b@example.com'});
      final typed = _list(_configuration, ancestorKeys: ['form_b']);
      expect(_entry(typed, 'TextField')['text'], 'b@example.com');
      final untouched = _list(_configuration, ancestorKeys: ['form_a']);
      expect(_entry(untouched, 'TextField')['text'], '');
    },
  );

  testWidgets('reports the effective state of radios and toggles', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        RadioGroup<int>(
          groupValue: 2,
          onChanged: (_) {},
          child: const Column(
            children: [
              Radio<int>(key: ValueKey('first'), value: 1),
              RadioListTile<int>(
                key: ValueKey('second'),
                value: 2,
                title: Text('Second'),
              ),
            ],
          ),
        ),
        Checkbox(tristate: true, value: null, onChanged: (_) {}),
        SwitchListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('Wi-Fi'),
        ),
      ]),
    );

    final elements = _list(_configuration);
    expect(_keyed(elements, 'first')['selected'], 'false');
    expect(_keyed(elements, 'second')['selected'], 'true');
    expect(_hasText(elements, 'Second'), isTrue);
    expect(_entry(elements, 'Checkbox')['value'], 'null');
    expect(_entry(elements, 'SwitchListTile')['value'], 'true');
  });

  testWidgets('a field or a button lists the toggle inside it on its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        TextField(
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: Switch(value: true, onChanged: (_) {}),
          ),
        ),
        OutlinedButton(
          onPressed: () {},
          child: Checkbox(value: true, onChanged: (_) {}),
        ),
      ]),
    );

    final elements = _list(_configuration);

    expect(_entry(elements, 'TextField'), isNot(contains('value')));
    expect(_entry(elements, 'OutlinedButton'), isNot(contains('value')));
    expect(_entry(elements, 'Switch')['value'], 'true');
    expect(_entry(elements, 'Checkbox')['value'], 'true');
  });

  testWidgets(
    'reports adaptive Material toggles on Apple platforms by themselves',
    (tester) async {
      await tester.pumpWidget(
        _app([
          Switch.adaptive(value: true, onChanged: (_) {}),
          Checkbox.adaptive(value: false, onChanged: (_) {}),
          RadioGroup<int>(
            groupValue: 1,
            onChanged: (_) {},
            child: const Radio<int>.adaptive(value: 1),
          ),
        ]),
      );

      final elements = _list(_configuration);

      expect(_configuration.uiLibraries, {MarionetteUiLibrary.materialUi});
      expect(_entry(elements, 'Switch')['value'], 'true');
      expect(_entry(elements, 'Checkbox')['value'], 'false');
      expect(_entry(elements, 'Radio<int>')['selected'], 'true');
      expect(
        elements.where((e) => '${e['type']}'.startsWith('Cupertino')),
        isEmpty,
      );
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );
}
