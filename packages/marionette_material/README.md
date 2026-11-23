# marionette_material

Marionette support for apps built with the [`material_ui`](https://pub.dev/packages/material_ui) widget library. Without it, Marionette does not recognize `material_ui` widgets as controls: they are missing from `get_interactive_elements`, and fields and toggles report no value.

Requires Flutter 3.44 or newer and Dart 3.12 or newer.

## Setup

Add the package next to `marionette_flutter`:

```bash
flutter pub add marionette_flutter marionette_material
```

Call `withMaterialUi()` on the configuration you already pass to the binding:

```dart
import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_material/marionette_material.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      const MarionetteConfiguration().withMaterialUi(),
    );
  }
  runApp(const MyApp());
}
```

Your own callbacks and settings stay in place, and calling `withMaterialUi()` again changes nothing. Restart the app after the change; a hot reload does not run `main()` again.

`material_ui` itself depends on `cupertino_ui`, but `marionette_material` does not depend on `marionette_cupertino`. An app that uses `cupertino_ui` widgets directly adds `marionette_cupertino` as well and calls both extensions on the same configuration, in either order:

```dart
import 'package:marionette_cupertino/marionette_cupertino.dart';
import 'package:marionette_material/marionette_material.dart';

MarionetteBinding.ensureInitialized(
  const MarionetteConfiguration().withMaterialUi().withCupertinoUi(),
);
```

## Supported widgets

- `ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton` and other `ButtonStyleButton` subclasses, `IconButton`, `FloatingActionButton` and `InkWell`
- `DropdownButton`, `DropdownButtonFormField` and `PopupMenuButton`
- `Slider`
- `Checkbox`, `CheckboxListTile`, `Radio`, `RadioListTile` (also inside a `RadioGroup`), `Switch` and `SwitchListTile`
- `Switch.adaptive`, `Checkbox.adaptive` and `Radio.adaptive`, also on iOS and macOS, where they draw Cupertino controls; `marionette_cupertino` is not needed for them
- `TextField` and `TextFormField`, also without a `controller`

Other `material_ui` widgets, such as chips, menus, date pickers and navigation bars, get no dedicated support. Marionette still lists their text and keyed widgets and taps them through the gesture detectors they contain.
