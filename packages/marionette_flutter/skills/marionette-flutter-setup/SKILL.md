---
name: marionette-flutter-setup
description: Prepare a Flutter app for an AI agent to drive with Marionette in debug or profile builds. Covers adding marionette_flutter, MarionetteBinding behind kDebugMode, marionette_material and marionette_cupertino for material_ui and cupertino_ui apps, MarionetteConfiguration for a custom design system (isInteractiveElement, extractText, Semantics), a LogCollector for get_logs, screenshot size, MarionetteDeviceConfig for set_device_config, session reports, the single-binding rule, aligned bridge versions, and the native lane's device setup (adb, WebDriverAgent, hosts). Use when adding Marionette to an app; when connect fails because the app has no binding, or with a version mismatch, or reports a missing UI integration; when the app hangs at startup or hits a binding assertion; when get_interactive_elements misses custom buttons or fields, or tap(text:) cannot find visible text; when get_logs has no collector; or when set_device_config returns setup steps. To drive a set-up app, use marionette-flutter-drive-app.
---

# marionette_flutter: set up an app

Marionette has two halves: **`marionette_flutter`**, the package in the app,
which registers a VM service extension per action (`ext.flutter.marionette.*`),
and the bridge the agent calls, **`marionette_mcp`** (MCP tools) or
**`marionette_cli`** (shell commands). This skill prepares the app for either
bridge and keeps the versions aligned. Driving the app is the job of
`marionette-flutter-drive-app`.

## Add the binding

`connect` (or any CLI command) only works if the target app initialized
`MarionetteBinding`. Check the entrypoint (or ask) before changing anything.
A binding that is already there does not end the setup: run *Check the source
first*, below, as well.

```bash
flutter pub add marionette_flutter
```

```dart
void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MyApp());
}
```

An app built on Flutter's own widgets needs nothing more. This runs inside
`main()`, so any time you add or change it, **hot restart** — a hot reload
doesn't re-execute `main()`, so the change will look like it did nothing. Gate every
piece of Marionette wiring behind `kDebugMode` (or `!kReleaseMode` — see
*Device-config sweeps*, below) so none of it ships in a release build: both
are compile-time constants the release branch survives cleanly.

## Apps on `material_ui` or `cupertino_ui`

`material_ui` and `cupertino_ui` are Flutter's Material and Cupertino widget
libraries published as pub packages. Marionette recognizes their widgets only
when the app adds the matching integration:

| The app's source uses | Add                    | Call on the configuration |
|-----------------------|------------------------|---------------------------|
| `material_ui`         | `marionette_material`  | `.withMaterialUi()`       |
| `cupertino_ui`        | `marionette_cupertino` | `.withCupertinoUi()`      |
| both                  | both packages          | both, in either order     |
| neither               | nothing                | nothing                   |

Both integrations need Flutter 3.44 or newer (Dart 3.12), and `material_ui`
1.1.0 or `cupertino_ui` 1.0.1 or newer; `marionette_flutter` alone keeps
Flutter 3.27.

### Check the source first

Run this check before each control or QA session, also when the binding is
already there, and again after a change to the dependencies, the entrypoint or
the Marionette configuration. Plain `flutter test` runs don't need it.

1. **The active app.** In a monorepo, take the package the user runs. Another
   app in the repository, with a different UI library, doesn't count.
2. **The entrypoint.** Find the file `flutter run` starts (`-t`, a flavor's
   `main_<flavor>.dart`) and where it initializes the binding.
3. **The libraries its source uses.** Search the app and the design-system
   packages it depends on (`.dart_tool/package_config.json` says where each
   one resolves) for imports and exports of `package:material_ui/` and
   `package:cupertino_ui/`, aliased ones (`as m`) included. A design-system
   package that re-exports one counts for every app that uses it.
4. **Not the lockfile.** `material_ui` depends on `cupertino_ui`, so
   `cupertino_ui` appears in `pubspec.lock`, `package_config.json` and the
   running app's libraries even when no source imports it. That alone never
   calls for `marionette_cupertino`: Material's adaptive controls
   (`Switch.adaptive`, `Checkbox.adaptive`, `Radio.adaptive`) need only
   `marionette_material`.

### Wire the integration

In the package of the active app:

```bash
flutter pub add marionette_material    # and/or marionette_cupertino
```

Call the extension on the configuration the app already passes. Its
callbacks, its binding (a combined `MarionetteBindingMixin` binding included)
and its `kDebugMode` or `!kReleaseMode` gate stay as they are:

```dart
MarionetteBinding.ensureInitialized(
  MarionetteConfiguration(
    isInteractiveElement: isMyInteractiveWidget, // the app's own callbacks stay
    enableSessionReports: true,
  ).withMaterialUi().withCupertinoUi(),
);
```

Running the setup again changes nothing: skip a dependency that is already in
`pubspec.yaml` and an extension that is already called, and never add a second
binding. If `flutter pub add` cannot resolve (an older Flutter, or a
`material_ui` or `cupertino_ui` below the minimum), report the conflict.
Don't upgrade Flutter or the UI library, add `dependency_overrides`, or copy
the integration's rules into the app to get past it.

Then run `flutter pub get` and `flutter analyze`, and **hot restart** or
relaunch the app (relaunch a profile build). A hot reload doesn't run `main()`
again, so it proves nothing.

### Verify

Pass the libraries step 3 found to `connect` as `required_ui_libraries` (`[]`
when the source uses neither). On the CLI, register the app and run
`marionette -i <name> doctor --required-ui-library material_ui`, repeating the
option for each library. The result names the package and extension to add when one is
missing; without a source-checked scope it stays unverified.

Then smoke-test the screen: a visible button, a field and a toggle or radio,
where the screen has them, are listed by `get_interactive_elements` with their
text, value or state, and `tap` and `enter_text` work on them. Report which
screens, controls, platform and build mode you checked. A control the screen
didn't show is not verified.

## Custom design system? Teach Marionette about it

Zero-config setup only recognizes Flutter's own widgets (`ElevatedButton`,
`TextField`, `Switch`, …) and extracts text only from `Text`, `RichText`,
`EditableText`, `TextField`, and `TextFormField`. If the app wraps its own
buttons, fields, or text — true of most production apps — `get_interactive_elements`
will look sparse and `tap(text: ...)` will fail to find things that are
clearly on screen. That's not a Marionette bug; it just doesn't know your
widgets yet:

```dart
MarionetteConfiguration(
  // Recognize your custom interactive widgets.
  isInteractiveElement: (element) => switch (element.widget) {
    MyButton() || MyTextField() => true,
    _ => false,
  },
  // Extract their visible text for text-based matching and discovery.
  extractText: (element) {
    final widget = element.widget;
    if (widget is MyText) return widget.data;
    return null;
  },
)
```

Pass it as `MarionetteBinding.ensureInitialized(MarionetteConfiguration(...))`.
For a non-trivial design system, extract the configuration to its own file
(e.g. `lib/debug/marionette_config.dart`) imported only behind `kDebugMode`,
rather than growing it inline in `main.dart` — that keeps release builds free
of design-system introspection helpers even before the compiler strips them.

`isInteractiveElement` and `extractText` receive the `Element`, not just the
`Widget`. Match with an `is` check or pattern on `element.widget` — that
covers generic widgets (`MySelect()` matches `MySelect<String>`) and
subclasses (`MyButton()` matches `MyPrimaryButton extends MyButton`), and can
read the widget's fields to decide per instance. `extractText` can also walk
the subtree when a label is itself a widget rather than a plain string.
If the app still uses the deprecated `isInteractiveWidget: (type) => ...` or
`shouldStopTraversal: (type) => ...`, move it to `isInteractiveElement` /
`shouldStopTraversalAtElement`: a `Type` only compares with exact `==`, so it
silently misses generic and subclassed widgets. While both are set, their
results are combined with OR.
Custom-painted text and badges reach no `Text` widget at all, and a
`WidgetSpan` is only a problem when its embedded content isn't itself built
from `Text`/`RichText` (an icon, a custom-painted chip) — plain text nested
inside one is still its own discoverable element. For genuinely non-text
content, annotate with `Semantics(label: ..., value: ...)` instead; Marionette surfaces that as a
`Semantics` element with the joined `'label: value'` string, and it costs
nothing if `label`/`value` are absent (unlabeled `Semantics` nodes are
silently skipped). That text is for discovery only: the text matcher ignores
it, so give the widget a key or `Semantics(identifier: ...)` when an agent
must act on it.

Not every custom widget needs an entry: add one when it's a primary
interactive primitive (button, field, toggle, tab, chip) or when
`get_interactive_elements` is noticeably missing it; skip widgets that are
only ever decorative, or ones that already wrap a primitive Marionette sees
(a `MyCard` built on `GestureDetector` is already covered). The list doesn't
need to be exhaustive up front — extend it as real use surfaces a missing
target.

One more `MarionetteConfiguration` field, `shouldStopTraversalAtElement`, is
worth naming only to warn against it: it's tempting to add a scroll container
there to "reduce traversal cost," but on a real production app that measurably
*dropped* widget coverage from 25.8% to 17.8% — the agent lost visibility into
everything nested below the cut, including the content it needed to reach.
Leave it `null` unless a profiler has shown a real, measured cost, and never
point it at a scrolling container.

## Logs for `get_logs`

Without a `LogCollector`, `get_logs` returns a message explaining how to add
one rather than actual logs. Pick whichever matches how the app already logs:

- Uses the `logging` package → `flutter pub add marionette_logging`, pass
  `LoggingLogCollector()` as `logCollector`.
- Uses the `logger` package → `flutter pub add marionette_logger`, pass
  `LoggerLogCollector()` (it doubles as a `LogOutput` for that package too).
- Anything else → `PrintLogCollector` (ships in `marionette_flutter`) exposes
  a manual `addLog(message)` to call from wherever logs already flow —
  routing Flutter's own `debugPrint` through it is a common choice, tee'd
  into the existing implementation rather than replacing it, to keep
  `debugPrintThrottled`'s throttling.

## Screenshot size

`take_screenshots` downscales captures to fit within 2000×2000 physical
pixels by default, to keep base64 payloads manageable. Override
`maxScreenshotSize` on `MarionetteConfiguration` if a screen needs more
detail (`Size(3000, 3000)`, say), or set it to `null` to disable resizing
entirely — but keep the default unless there's a concrete reason to raise it,
since larger screenshots mean larger payloads on every call.

## Device-config sweeps

`set_device_config` — sweeping text scale, bold text, or light/dark
appearance without touching real OS settings — is the one capability that
needs a widget in the tree, since Marionette won't insert one into an app
behind its back:

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

Without it, `set_device_config` responds with these setup instructions
instead of succeeding. Because it lives in `main()`, adding it also needs a
hot **restart**. `!kReleaseMode` (rather than `kDebugMode`) is the better gate
here because it additionally covers profile builds, where the VM service is
still reachable — use the same gate for both the binding and this widget,
since gating the widget more loosely than the binding gains nothing (it
degrades to a no-op child-passthrough if the binding isn't there, so a missed
gate costs one inert element, never a crash).

## The single-binding rule

Flutter allows exactly one `WidgetsBinding` per process. Marionette can be
combined with another binding when both behaviors are available as mixins:
create one class, apply `MarionetteBindingMixin` last, and initialize it before
either package touches `WidgetsBinding`.

```dart
class AppBinding extends WidgetsFlutterBinding
    with OtherBindingMixin, MarionetteBindingMixin {
  AppBinding(this.configuration);

  @override
  final MarionetteConfiguration configuration;
}

void main() {
  if (kDebugMode) {
    MarionetteBindingMixin.ensureInitialized(
      () => AppBinding(const MarionetteConfiguration()),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MyApp());
}
```

`MarionetteBindingMixin.ensureInitialized` checks for an existing binding
before calling the factory. If another binding got there first, it reports a
clear error and does not construct a second one. A direct `AppBinding()` call
bypasses that guard. This does not retrofit a binding that is already
installed; use a combined binding or a test-specific entrypoint.

- **`flutter test`** running `main()` under `kDebugMode` collides with
  `AutomatedTestWidgetsFlutterBinding`. Guard against it —
  `Platform.environment.containsKey('FLUTTER_TEST')` — or give tests a
  separate entrypoint that skips Marionette entirely.
- **Sentry** is the known silent offender: `SentryFlutter.init()` may call
  `WidgetsBinding.ensureInitialized()` inside its `appRunner`-wrapping zone
  before your code runs. Initialize the combined binding, or plain Marionette,
  before Sentry when the app does not need Sentry's binding-specific frame
  instrumentation. Keep binding initialization and `runApp` in the same
  Flutter zone.

## Version alignment

The MCP `connect` tool checks that `marionette_mcp` and the app's
`marionette_flutter` are on the same version, and fails with a clear message
rather than a confusing runtime error if they aren't. The CLI does not
perform this check — a stale `marionette_flutter` there can fail in less
obvious ways instead of a clear mismatch error. Either way, don't chase a
mismatch by retrying — align the versions: `flutter pub add marionette_flutter`
in the app, and `dart pub global activate marionette_mcp`/`marionette_cli`
for the bridge (or `dart pub add dev:marionette_mcp`/`dev:marionette_cli` if
you'd rather pin it as a dev dependency instead of a global tool).

## Session reports

`MarionetteConfiguration(enableSessionReports: true)` makes every run leave a folder
under `.marionette/sessions/`: the server's `steps.md`, the screenshots and the
agent's `report.md` (see `marionette-flutter-drive-app`). Turn it on when the user
asks for reports, or for Patrol tests from a run: `marionette-flutter-to-patrol` reads
that folder. The server gitignores `.marionette/` itself. It is binding
configuration, so it needs a hot restart.

## Native lane setup

The native lane (`native_*` tools, `native-*` CLI commands) drives UI outside
the Flutter tree: permission dialogs, pickers, WebViews, notifications. The app
needs nothing new — it doesn't go through `MarionetteBinding` — but every flow
still starts in an app reached with `connect`. The device needs setup:

- **Hosts:** macOS and Linux. Windows is not supported.
- **Android:** `adb` on `PATH` and a device or emulator. Marionette downloads
  and installs UIAutomator2 itself on the first `native_connect`.
- **iOS:** the **Simulator only** (not physical iPhones yet), on macOS with
  Xcode, one iOS Simulator at a time, and a one-time WebDriverAgent build —
  the steps are on the
  [Native lane](https://marionette.leancode.co/docs/native/#setup) docs page.

Driving it is in `marionette-flutter-drive-app` and its native-lane reference.

## Next

When `connect` succeeds, its UI integration check passes and
`get_interactive_elements` lists the screen's buttons and fields, the app is
ready: drive it with
`marionette-flutter-drive-app`.
