import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_cupertino/marionette_cupertino.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/info_extensions.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_material/marionette_material.dart';
import 'package:marionette_ui_integrations_fixture/src/fixture_material_app.dart';
import 'package:marionette_ui_integrations_fixture/src/mixed_controls.dart';

/// Lists elements the way `marionette.interactiveElements` does.
List<Map<String, dynamic>> _list(MarionetteConfiguration configuration) {
  return findScopedInteractiveElements(
    const {},
    elementTreeFinder: ElementTreeFinder(configuration),
    widgetFinder: WidgetFinder(),
    configuration: configuration,
  );
}

Iterable<Map<String, dynamic>> _ofType(
  List<Map<String, dynamic>> elements,
  String type,
) {
  return elements.where((e) => e['type'] == type);
}

/// Shows the app in a window wide enough for all three sections.
Future<void> _pumpMixedApp(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1200, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const FixtureMaterialApp(child: MixedControls()));
}

void main() {
  testWidgets('composes both integrations in either order and once', (
    tester,
  ) async {
    await _pumpMixedApp(tester);
    final materialFirst = const MarionetteConfiguration()
        .withMaterialUi()
        .withCupertinoUi();
    final cupertinoFirst = const MarionetteConfiguration()
        .withCupertinoUi()
        .withMaterialUi();

    expect(materialFirst.withMaterialUi(), same(materialFirst));
    expect(materialFirst.withCupertinoUi(), same(materialFirst));
    expect(cupertinoFirst.uiLibraries, materialFirst.uiLibraries);

    final elements = _list(materialFirst);

    expect(_list(cupertinoFirst), elements);
    expect(_ofType(elements, 'CupertinoButton').single['text'], 'Save');
    expect(_ofType(elements, 'CupertinoTextField').single['label'], 'Name');
    expect(_ofType(elements, 'CupertinoSwitch').single['value'], 'false');
  });

  testWidgets('lists an adaptive checkbox once, as a Material control', (
    tester,
  ) async {
    await _pumpMixedApp(tester);

    final elements = _list(
      const MarionetteConfiguration().withMaterialUi().withCupertinoUi(),
    );
    final adaptive = elements
        .where((e) => e['key'] == 'adaptive_checkbox')
        .single;

    expect(adaptive['type'], 'Checkbox');
    expect(adaptive['value'], 'false');
    // The Cupertino section's own checkbox is the only Cupertino one.
    expect(_ofType(elements, 'CupertinoCheckbox'), hasLength(1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
