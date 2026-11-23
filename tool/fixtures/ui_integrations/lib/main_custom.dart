import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_material/marionette_material.dart';
import 'package:material_ui/material_ui.dart';

import 'src/fixture_material_app.dart';
import 'src/material_ui_controls.dart';

/// A `material_ui` app whose own configuration the Material integration
/// extends: its field label wins over the integration's, and its other
/// settings stay.
void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(
        compaction: CompactionMode.none,
        extractFieldLabel: (element) =>
            element.widget is TextField ? 'Customer name' : null,
      ).withMaterialUi(),
    );
  }
  runApp(const FixtureMaterialApp(child: MaterialUiControls()));
}
