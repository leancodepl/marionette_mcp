# Flutter Setup

How to wire `MarionetteBinding` into your app, and the one rule you must not break.

## The binding

`MarionetteBinding.ensureInitialized()` registers the VM service extensions (`ext.flutter.marionette.*`) that the MCP server and CLI talk to. Initialize it in `main()`, gated on `kDebugMode` so it never ships in release builds:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  runApp(const MyApp());
}
```

`ensureInitialized` takes an optional positional `MarionetteConfiguration`. Omitting it (as above) uses the defaults. To recognize custom widgets, collect logs, or tune screenshots, pass a configuration — see [Configuration](./configuration.md).

## Basic setup works for raw Material widgets only

The zero-config setup above recognizes the **standard Flutter widgets**: buttons (`ElevatedButton`, `TextButton`, `IconButton`, …), `TextField`/`TextFormField`, `Switch`, `Checkbox`, `Slider`, and a few more, plus text from `Text`/`RichText`. See the full built-in lists in [Configuration → What works out of the box](./configuration.md#what-works-out-of-the-box).

> [!IMPORTANT]
> If your app uses a **custom design system** — wrapped buttons, custom text fields, bespoke controls — the defaults will **not** see them, and the agent won't be able to find or tap them by text. This is the single most common source of "it doesn't work" reports. If that's you (it's most production apps), go straight to the [Production Setup Checklist](./configuration.md#production-setup-checklist).

## Single-binding rule

Flutter allows only **one** `WidgetsBinding` per process. `MarionetteBinding` is a binding. If another binding (e.g. `AutomatedTestWidgetsFlutterBinding` from `flutter test`, or `IntegrationTestWidgetsFlutterBinding`) is already initialized, calling `MarionetteBinding.ensureInitialized()` throws a binding assertion error.

This commonly bites when your test calls `main()` and `kDebugMode` is `true` during tests. Two ways to avoid it:

### Option A — Skip Marionette under `flutter test`

```dart
import 'dart:io' show Platform;

final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
if (kDebugMode && !isFlutterTest) {
  MarionetteBinding.ensureInitialized();
} else {
  WidgetsFlutterBinding.ensureInitialized();
}
```

### Option B — Use a separate test entrypoint

Keep `MarionetteBinding` in your production `main()` (`lib/main.dart`) and create a different entrypoint for tests (e.g. `lib/main_test.dart`) that does **not** initialize `MarionetteBinding`.

## Next steps

- [Configuration](./configuration.md) — custom widgets, the production checklist, and a complete `main.dart`.
- [Log Collection](./logging.md) — wire up `get_logs`.
- [Troubleshooting](./troubleshooting.md) — common gotchas.
