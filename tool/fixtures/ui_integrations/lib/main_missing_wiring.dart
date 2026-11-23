import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'src/fixture_material_app.dart';
import 'src/material_ui_controls.dart';

/// A `material_ui` app whose binding lacks the Material integration, for the
/// missing-integration diagnosis and its repair.
void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized(const MarionetteConfiguration());
  }
  runApp(const FixtureMaterialApp(child: MaterialUiControls()));
}
