---
name: marionette-flutter-setup
description: Prepare a Flutter app for Marionette, so an AI agent can drive it in debug or profile builds. Covers adding marionette_flutter, MarionetteBinding behind kDebugMode, MarionetteConfiguration for a custom design system (isInteractiveElement, extractText, Semantics), a LogCollector for get_logs, screenshot size, MarionetteDeviceConfig for set_device_config, session reports, the single-binding rule, and matching marionette_mcp or marionette_cli versions. Use when adding Marionette to an app; when connect fails because the app has no binding, or with a version mismatch; when the app hangs at startup or hits a binding assertion after adding Marionette; when get_interactive_elements misses custom buttons or fields, or tap(text:) cannot find visible text; when get_logs says no collector is configured; or when set_device_config returns setup instructions. To drive an app that is already set up, use marionette-flutter-drive-app.
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
`MarionetteBinding`. Check `main.dart` (or ask) before changing anything — if
the binding is already there and the agent can see the app's widgets, the app
is ready.

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

This is all a standard Material-widgets app needs. It runs inside `main()`, so
any time you add or change it, **hot restart** — a hot reload doesn't
re-execute `main()`, so the change will look like it did nothing. Gate every
piece of Marionette wiring behind `kDebugMode` (or `!kReleaseMode` — see
*Device-config sweeps*, below) so none of it ships in a release build: both
are compile-time constants the release branch survives cleanly.

## Custom design system? Teach Marionette about it

Zero-config setup only recognizes stock Material widgets (`ElevatedButton`,
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
silently skipped).

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

Flutter allows exactly one `WidgetsBinding` per process. If something else
claims it first, `MarionetteBinding.ensureInitialized()` throws a clear
error — except with one real offender, where it doesn't:

- **`flutter test`** running `main()` under `kDebugMode` collides with
  `AutomatedTestWidgetsFlutterBinding`. Guard against it —
  `Platform.environment.containsKey('FLUTTER_TEST')` — or give tests a
  separate entrypoint that skips `MarionetteBinding` entirely.
- **Sentry** is the known silent offender: `SentryFlutter.init()` always calls
  `WidgetsBinding.ensureInitialized()` inside its own `appRunner`-wrapping
  zone before your code runs, and it swallows the resulting binding error as
  if it were a reportable crash — so the app just hangs on the splash screen
  forever with no exception, no crash, and no log output. The fix is
  initialization order: call `MarionetteBinding.ensureInitialized()`
  **before** `SentryFlutter.init()`, not inside its `appRunner`. Sentry checks
  for an existing binding first and reuses it, so going first avoids the
  conflict entirely. The same ordering fix applies to any other plugin whose
  `init()` touches `WidgetsBinding` ahead of your `appRunner`.

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

## Next

When `connect` succeeds and `get_interactive_elements` lists the screen's
buttons and fields, the app is ready: drive it with
`marionette-flutter-drive-app`.
