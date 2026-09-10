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

## Opting in to device config overrides

`set_device_config` — overriding text scale, bold text, or light/dark appearance in the running app — is the one tool that needs a change beyond the binding. Marionette will not insert a widget into your tree behind your back, so your app mounts one:

```dart
void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized();
    runApp(const MarionetteDeviceConfig(child: MyApp()));
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp());
  }
}
```

`MarionetteDeviceConfig` applies the overrides through a `MediaQuery` above your app, which is where `MaterialApp` takes its platform data from — so they reach the whole tree, theme resolution included.

Both the binding and the widget sit behind `!kReleaseMode`. It's a compile-time constant, so the release branch is the only one that survives compilation and neither reaches your release binary.

The [binding section above](#the-binding) gates on `kDebugMode`, which is the stricter choice and fine if you only ever drive Marionette in debug. `!kReleaseMode` additionally covers profile builds, where the VM service is also available. Pick one and use it for both the binding and the widget — gating the widget more loosely than the binding gains nothing, since without the binding the widget is inert.

Should the gate ever be missed, the widget degrades on its own: with no binding installed it builds its child unchanged, costing one inert element.

Leave it out and the tool stays inert: `set_device_config` answers with these setup instructions instead of reporting success on a no-op. Note that this lives in `main()`, which a hot reload does not re-run — **hot restart** after adding it.

## Next steps

- [Configuration](./configuration.md) — custom widgets, the production checklist, and a complete `main.dart`.
- [Log Collection](./logging.md) — wire up `get_logs`.
- [Troubleshooting](./troubleshooting.md) — common gotchas.
