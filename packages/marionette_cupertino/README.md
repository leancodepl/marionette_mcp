# marionette_cupertino

Marionette support for apps built with the [`cupertino_ui`](https://pub.dev/packages/cupertino_ui) widget library. Without it, Marionette does not recognize `cupertino_ui` widgets as controls: they are missing from `get_interactive_elements`, and fields and toggles report no value.

Requires Flutter 3.44 or newer and Dart 3.12 or newer.

## Setup

Add the package next to `marionette_flutter`:

```bash
flutter pub add marionette_flutter marionette_cupertino
```

Call `withCupertinoUi()` on the configuration you already pass to the binding:

```dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:marionette_cupertino/marionette_cupertino.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      const MarionetteConfiguration().withCupertinoUi(),
    );
  }
  runApp(const MyApp());
}
```

Your own callbacks and settings stay in place, and calling `withCupertinoUi()` again changes nothing. Restart the app after the change; a hot reload does not run `main()` again.

An app that also uses `material_ui` adds `marionette_material` as well and calls both extensions on the same configuration, in either order: `configuration.withMaterialUi().withCupertinoUi()`. `marionette_cupertino` does not depend on `material_ui` or `marionette_material`.

## Supported widgets

- `CupertinoButton`
- `CupertinoTextField` and `CupertinoSearchTextField`, also without a `controller`
- `CupertinoCheckbox`, `CupertinoRadio` (also inside a `RadioGroup`) and `CupertinoSwitch`
- `CupertinoSlider`
- `CupertinoSegmentedControl` and `CupertinoSlidingSegmentedControl`

Other `cupertino_ui` widgets, such as pickers, date pickers, context menus and list tiles, get no dedicated support. Marionette still lists their text and keyed widgets and taps them through the gesture detectors they contain.
