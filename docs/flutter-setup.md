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

Flutter allows only **one** `WidgetsBinding` per process. `MarionetteBinding` is a binding. If another binding (e.g. `AutomatedTestWidgetsFlutterBinding` from `flutter test`, or `IntegrationTestWidgetsFlutterBinding`) is already initialized, calling `MarionetteBinding.ensureInitialized()` throws a clear error telling you which binding got there first.

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

### Watch out for plugins that install their own binding

The same rule bites in production, not just under `flutter test`. Some plugins install their own `WidgetsBinding` subclass as part of their own initialization, before your app code runs. Sentry is one example.

#### Sentry

`SentryFlutter.init()` always registers a `WidgetsFlutterBindingIntegration` that calls `WidgetsBinding.ensureInitialized()` before invoking `appRunner` — so if `MarionetteBinding.ensureInitialized()` is the first line of your `appRunner`, the "real" binding has already been claimed by Sentry by the time it runs.

Normally this would throw immediately and you'd notice right away. With Sentry it doesn't: the app just hangs on the native splash screen forever, with **no exception, no crash, and no log output**. That's because `appRunner` executes inside Sentry's own error-capturing zone, which intercepts the binding error as if it were a reportable crash instead of letting it surface to your console — so nothing after the `ensureInitialized()` call ever runs, including `runApp()`. See [#96](https://github.com/leancodepl/marionette_mcp/issues/96) for a full repro.

The fix is to initialize `MarionetteBinding` **before** `SentryFlutter.init()`, not inside its `appRunner`:

```dart
void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  SentryFlutter.init(
    (options) => options.dsn = _sentryDsn,
    appRunner: () => runApp(const MyApp()),
  );
}
```

Sentry's own binding setup checks for an existing `WidgetsBinding` first and reuses it rather than replacing it, so initializing Marionette first avoids the conflict entirely. The same fix applies to any other plugin whose `init()` touches `WidgetsBinding` ahead of your `appRunner`.

## Next steps

- [Configuration](./configuration.md) — custom widgets, the production checklist, and a complete `main.dart`.
- [Log Collection](./logging.md) — wire up `get_logs`.
- [Troubleshooting](./troubleshooting.md) — common gotchas.
