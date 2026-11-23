# UI integrations fixture

Apps that check `marionette_material` and `marionette_cupertino` against a running app. Each entrypoint wires the binding differently:

| Entrypoint | UI libraries | Binding configuration |
|------------|--------------|-----------------------|
| `lib/main_material.dart` | `material_ui` | `withMaterialUi()` |
| `lib/main_cupertino.dart` | `cupertino_ui` only | `withCupertinoUi()` |
| `lib/main_mixed.dart` | SDK Material, `material_ui` and `cupertino_ui` | `withMaterialUi().withCupertinoUi()` |
| `lib/main_custom.dart` | `material_ui` | the app's own settings and field label, then `withMaterialUi()` |
| `lib/main_missing_wiring.dart` | `material_ui` | no integration, for the missing-integration report |

The `material_ui` and `cupertino_ui` sections have a button, a text field, a tristate checkbox, a switch and a radio group under the same keys (`save`, `name`, `terms`, `notifications`, `size_s`, `size_m`). The SDK Material section has only the button, the field and a two-state checkbox (`save`, `name`, `terms`). Every section has a `status` text with what the controls received. In the mixed app, the sections are keyed `sdk`, `material` and `cupertino`; use `ancestor_keys` to pick one. The `material_ui` section also has adaptive toggles under an iOS theme, and the `cupertino_ui` section a segmented control (`period`).

Run one on the Linux desktop or in Chrome:

```bash
cd tool/fixtures/ui_integrations
flutter run -d linux -t lib/main_mixed.dart
```

The Cupertino-only entrypoint imports no `material_ui`, but this package depends on both libraries. `dart tool/check_min_sdk.dart addons` checks the dependency graphs of Cupertino-only, Material-only and mixed apps.
