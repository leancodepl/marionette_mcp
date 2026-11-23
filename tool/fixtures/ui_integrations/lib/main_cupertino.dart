import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:marionette_cupertino/marionette_cupertino.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'src/cupertino_ui_controls.dart';

/// A `cupertino_ui` app with the Cupertino integration and no `material_ui`
/// import.
void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized(
      const MarionetteConfiguration().withCupertinoUi(),
    );
  }
  runApp(
    const CupertinoApp(
      home: CupertinoPageScaffold(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: CupertinoUiControls(),
          ),
        ),
      ),
    ),
  );
}
