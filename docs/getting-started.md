# Getting Started

This guide takes you from zero to driving a running Flutter app with an AI agent in a few minutes. It covers the happy path: standard Material widgets, no custom configuration. If your app uses a custom design system, you'll also want [Configuration](./configuration.md) — but start here first.

## Overview

Marionette has two halves:

- **`marionette_flutter`** — a package you add to your Flutter app. It installs a binding that exposes VM service extensions the tooling talks to.
- **`marionette_mcp`** (or **`marionette_cli`**) — the bridge your AI agent runs. It connects to your app's VM service and translates agent requests into actions.

You always need `marionette_flutter` in the app. Whether you use the MCP server or the CLI depends on your agent — see [MCP Tools](./mcp-tools.md) and the [CLI guide](./cli.md).

## 1. Add the Flutter package

In your Flutter app directory:

```bash
flutter pub add marionette_flutter
```

## 2. Initialize the binding

Initialize `MarionetteBinding` in your `main()`, **only in debug mode**. For an app built from standard Material widgets, the defaults work out of the box:

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

> [!IMPORTANT]
> `MarionetteBinding` must be the **only** binding initialized in the process. If your tests call `main()` while `kDebugMode` is true, this will clash with the test binding. See [Flutter Setup](./flutter-setup.md#single-binding-rule) for the fix.

## 3. Install the agent bridge

Activate the MCP server as a global tool:

```bash
dart pub global activate marionette_mcp
```

Then register it with your AI tool. The exact command varies — see [Configuring your AI tool](./mcp-tools.md#configuring-your-ai-tool). For Claude Code:

```bash
claude mcp add --transport stdio marionette -- marionette_mcp
```

> Working in a constrained environment that can't run an MCP server? Use the [CLI](./cli.md) instead — any agent that can run shell commands can drive Marionette.

## 4. Run your app and grab the VM service URI

Run your app in debug mode:

```bash
flutter run
```

Look for the VM service URI in the console — the `ws://...` part:

```
The Flutter DevTools debugger and profiler ... is available at:
http://127.0.0.1:9101?uri=ws://127.0.0.1:9101/ws
```

Here the URI you want is `ws://127.0.0.1:9101/ws`.

> [!TIP]
> Pasting the URI manually is the most reliable workflow. Some tooling can infer it, but copy-pasting from `flutter run` output avoids surprises.

## 5. Connect and interact

Ask your agent to connect and explore. For example:

> "Connect to the app at `ws://127.0.0.1:9101/ws`, list the interactive elements, then tap the button labeled 'Sign in'."

Under the hood the agent will:

1. Call `connect` with the URI.
2. Call `get_interactive_elements` to see what's on screen.
3. Call `tap` (by key or visible text) to act.

That's the full loop. From here:

- **Using custom widgets?** Most real apps do. Continue to [Configuration](./configuration.md) — it explains why custom buttons/fields are invisible by default and how the [Production Setup Checklist](./configuration.md#production-setup-checklist) fixes it.
- **Want logs?** See [Log Collection](./logging.md).
- **Something not working?** See [Troubleshooting](./troubleshooting.md).
