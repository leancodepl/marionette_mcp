import 'package:flutter/foundation.dart';
import 'package:marionette_cupertino/marionette_cupertino.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_material/marionette_material.dart';
import 'package:material_ui/material_ui.dart';

import 'src/fixture_material_app.dart';
import 'src/mixed_controls.dart';

/// An app with the SDK's Material widgets, `material_ui` and `cupertino_ui`,
/// and both integrations on one binding.
void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized(
      const MarionetteConfiguration().withMaterialUi().withCupertinoUi(),
    );
  }
  runApp(const FixtureMaterialApp(child: MixedControls()));
}
