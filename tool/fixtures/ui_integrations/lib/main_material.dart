import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_material/marionette_material.dart';
import 'package:material_ui/material_ui.dart';

import 'src/fixture_material_app.dart';
import 'src/material_ui_controls.dart';

/// A `material_ui` app with the Material integration.
void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized(
      const MarionetteConfiguration().withMaterialUi(),
    );
  }
  runApp(const FixtureMaterialApp(child: MaterialUiControls()));
}
