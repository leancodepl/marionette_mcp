---
name: marionette-drive-flutter-apps
description: Connect to and drive a running Flutter app (debug or profile mode) with Marionette — inspect the widget tree, tap/swipe/type, take screenshots, read logs, hot reload/restart, sweep text-scale/dark-mode, and call app-specific extensions — via the marionette_mcp tools or the marionette CLI. Use whenever the user asks to test, click through, smoke-test, automate, QA, or interact with a Flutter app, or whenever a Marionette tool call fails, returns "not connected", can't find an element, or reports a version mismatch. Also load this when adding marionette_flutter to an app, wiring MarionetteConfiguration for a custom design system, or registering a custom extension.
---

# marionette

Marionette lets an AI agent drive a **running** Flutter app (debug or profile — never
release) the way it would a real user: read the screen, tap, type, scroll, screenshot,
read logs, hot reload. It has two halves:

- **`marionette_flutter`** — a package added to the target app. It registers a VM
  service extension per action (`ext.flutter.marionette.*`).
- **The bridge** — either **`marionette_mcp`** (MCP tools, e.g. `connect`, `tap`,
  `get_interactive_elements`) or **`marionette_cli`** (shell commands, e.g.
  `marionette tap --key ...`). Same capabilities, different transport. Prefer the MCP
  tools when they're in your tool list; fall back to the CLI in restricted
  environments (enterprise policy, a shell-only agent) — run `marionette help-ai`
  once at the start of such a session and follow its reference for exact syntax.

Both talk to the same underlying VM service extensions, so everything below applies to
either transport — action names differ only in casing (`get_interactive_elements` vs
`get-interactive-elements`).

## Before driving anything: is the app set up?

`connect` (or any CLI command) only works if the target app initialized
`MarionetteBinding`. If you're not sure, check `main.dart` (or ask). Minimal setup:

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

If it's missing: `flutter pub add marionette_flutter`, add the snippet above, then
**hot restart** (this runs in `main()`, which hot reload doesn't re-execute).

Two things worth checking before you start tapping:

- **Custom design system?** The zero-config setup only recognizes stock Material
  widgets (`ElevatedButton`, `TextField`, `Switch`, …) and plain `Text`/`RichText` for
  matching by visible text. If the app wraps its own buttons/fields/text — true of
  most production apps — `get_interactive_elements` will look empty or incomplete and
  `tap(text: ...)` will silently fail to find things that are clearly on screen. This
  is **not a Marionette bug**; it needs `MarionetteConfiguration.isInteractiveWidget`
  and `extractText` wired to the app's own widget types. Point whoever owns the app at
  the Production Setup Checklist in `docs/configuration.md` rather than working around
  it with raw coordinates.
- **Version match.** `connect` checks that `marionette_mcp`/`marionette_cli` and the
  app's `marionette_flutter` are the same version and fails with a clear message if
  not. Don't try to work around this by retrying — align the versions
  (`flutter pub add marionette_flutter` in the app,
  `dart pub global activate marionette_mcp`/`marionette_cli` for the bridge).

## Connecting

Every action requires a VM service WebSocket URI (`ws://127.0.0.1:PORT/TOKEN=/ws`),
found in the app's `flutter run` console output. Call `connect` (MCP) or pass `--uri`
/ a registered `-i <name>` (CLI) with that URI before anything else. For the CLI,
prefer `--uri` for one-off sessions and `marionette register <name> <uri>` +
`-i <name>` when you'll issue many commands against the same app.

## What you can do once connected

| Category | Actions | Notes |
| --- | --- | --- |
| Inspection | `get_interactive_elements`, `take_screenshots`, `get_logs` | `get_interactive_elements` is how you "see" the screen — call it before guessing at a target. `get_logs` needs a `LogCollector` wired up app-side; otherwise it returns setup instructions instead of an error. |
| Gestures | `tap`, `secondary_tap`, `double_tap`, `long_press`, `swipe`, `pinch_zoom`, `scroll_to`, `press_back_button` | Match by `key` › `identifier` › `text` › `type` › coordinates, in that preference order (see below). `secondary_tap` is desktop-only. |
| Text input | `enter_text`, `press_key` | `enter_text` overwrites a field's value directly. `press_key` sends a real key event (submit on `enter`, shortcuts with `modifiers`) but only edits in-place on desktop/web — on mobile, field editing still needs `enter_text`. |
| Device config | `set_device_config` | Sweeps text scale / bold text / light-dark under the app's *current* screen, without touching OS settings. Requires the app to opt in with `MarionetteDeviceConfig` (see below) — otherwise it returns setup instructions rather than failing. |
| Custom extensions | `list_custom_extensions`, `call_custom_extension`, plus any first-class tool an app registered with a schema | App-specific actions (navigate by route, seed test data, toggle a flag) the generic tools can't express. Call `list_custom_extensions` once to see what's available before assuming something isn't possible. |
| Dev workflow | `hot_reload`, `hot_restart` | `hot_reload` preserves state; use `hot_restart` only for changes a reload can't pick up (main()/bootstrap edits, global singletons, state shape) — requires the app to be running via `flutter run`. |
| Session | `connect`, `disconnect` | `connect` must be called before any other tool; a second `connect` implicitly disconnects the first. |

This mirrors (and should stay in sync with) `docs/mcp-tools.md` and the CLI's own
`marionette help-ai` reference — if either drifts from this list after a release,
trust the docs/CLI output over this file and flag the gap (see *Keeping this skill in
sync*, below).

## Good practices

- **Look before you act.** Call `get_interactive_elements` (or `take_screenshots` for
  a visual check) before the first gesture on a new screen, and again after a
  navigation you didn't drive step-by-step. Don't infer what's on screen from memory
  of the source code — the point of Marionette is to check the *running* state.
- **Selector priority: `key` > `identifier` > `text` > `type`/coordinates.** Keys
  (`ValueKey<String>`) and Semantics `identifier`s are stable across copy changes,
  localization, and refactors; `text` breaks the moment a label is edited or
  translated; coordinates break on any layout shift, font-scale change, or screen size
  difference. Reach for coordinates only as a last-resort diagnostic, never as the
  normal way to target something — if nothing else works, that's a sign the widget
  needs a key or a `Semantics(identifier: ...)`, not a sign to keep using coordinates.
- **An element "not found" is usually a configuration gap, not a bug.** Before
  concluding a widget can't be reached, check whether it's a custom widget type that
  needs `isInteractiveWidget`/`extractText`, or custom-painted/`WidgetSpan` content
  that needs a `Semantics(label:/value:)` annotation. Only after ruling those out is it
  worth suspecting an actual limitation.
- **Never suggest trimming `shouldStopTraversal` to "speed up" discovery**, and
  especially never add a scroll container to it. Measured on a real production app,
  filtering scroll containers out of traversal *dropped* widget coverage from 25.8% to
  17.8% — the agent lost visibility into everything nested below the cut, including
  the very content it needed to reach. Leave it `null` unless there's a profiled,
  measured reason not to.
- **`set_device_config` needs an opt-in widget, and the fix needs a hot *restart*.**
  If the tool comes back with setup instructions instead of success, the app hasn't
  wrapped its root in `MarionetteDeviceConfig`:

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

  Because this lives in `main()`, adding it takes a hot **restart** to take effect —
  a hot reload will look like it did nothing. Keep it (and the binding) behind
  `!kReleaseMode`/`kDebugMode` so neither reaches a release build; the widget degrades
  to a no-op on its own if the binding is missing, so forgetting the gate costs one
  inert element, not a crash.
- **Never let Marionette-only code leak into a release build.** Every snippet above is
  gated on `kDebugMode` or `!kReleaseMode` for a reason — both are compile-time
  constants that the release branch survives, the debug/profile one doesn't. If you're
  adding any Marionette wiring to an app, keep that gate.
- **Watch for the single-binding rule when adding the binding to an existing app.**
  Only one `WidgetsBinding` can exist per process. If `flutter test` runs `main()`
  under `kDebugMode`, or a plugin (Sentry is the known offender) installs its own
  binding before your `appRunner` runs, `MarionetteBinding.ensureInitialized()` will
  either throw or — with Sentry specifically — hang the app on the splash screen with
  no error at all. Initialize `MarionetteBinding` **before** `SentryFlutter.init()` (or
  any similar plugin init), and exclude `flutter test` runs
  (`Platform.environment.containsKey('FLUTTER_TEST')`) or use a separate test
  entrypoint. Full detail: `docs/flutter-setup.md#single-binding-rule`.
- **Confirm side effects with `get_logs`, not just UI state.** A tap looking like it
  worked isn't the same as the network call actually firing. If the app has a
  `LogCollector` wired up, check logs to confirm — and if it doesn't, that's worth
  telling the app owner about (`docs/logging.md` has three drop-in options).
- **Give the agent — including yourself in a later turn — the context an app owner
  has and Marionette doesn't.** Marionette can see the widget tree and act on it, but
  it has no idea what your product's flows, naming conventions, or edge cases are.
  When asked to "test the signup flow," state (or record) which screen to reach,
  expected keys/labels, and what success looks like, rather than assuming that's
  inferable from the UI alone.
- **Treat every gesture as best-effort.** Focus, text entry, and scrolling are
  simulations of user input and can behave differently across platforms, custom
  widgets, or overlays. If something is consistently flaky rather than occasionally
  so, that's a signal to add a key/identifier or a `MarionetteConfiguration` hook
  server-side, not to retry harder.

## Custom extensions

Apps can expose their own actions via `registerMarionetteExtension` (route
navigation, seeding test data, feature-flag toggles — anything the generic tools can't
express). Call `list_custom_extensions` before assuming an action isn't possible.
Extensions declaring a scalar `inputSchema` show up as first-class, individually named
tools (sanitized to `[a-z0-9_-]`, e.g. `appNavigation.goToPage` →
`app_navigation_go_to_page`) with validated arguments; schema-less ones are only
reachable through the generic `call_custom_extension`, passing the *real* (unsanitized)
name and key-value args. Full mechanics: `docs/custom-extensions.md`.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| "Not connected to any app" | No successful `connect` yet in this session | `connect` before anything else — see *Connecting*, above |
| `connect` fails with a version mismatch | `marionette_mcp`/`marionette_cli` and `marionette_flutter` are different versions | Align both to the same version |
| Custom buttons/fields don't show up in `get_interactive_elements` | Widget type isn't recognized as interactive | `MarionetteConfiguration.isInteractiveWidget` (`docs/configuration.md`) |
| `tap(text:)`/`scroll_to(text:)` can't find a visible label | Text isn't extracted from that widget | `MarionetteConfiguration.extractText` |
| Custom-painted text, badges, charts invisible to the agent | Never reaches a `Text` widget | `Semantics(label:/value:)` (`docs/semantics.md`) |
| `get_logs` says no collector configured | No `LogCollector` wired up | `docs/logging.md` |
| `set_device_config` returns setup instructions instead of succeeding | App hasn't opted in | Wrap root widget in `MarionetteDeviceConfig`, then **hot restart** |
| Binding assertion error on startup (often under `flutter test`) | Two `WidgetsBinding`s initialized | `docs/flutter-setup.md#single-binding-rule` |
| Everything above checks out but it still doesn't work in release mode | Marionette only runs in debug/profile | Not supported by design — verify you're not testing a release build |

## CLI fallback

When MCP tools aren't available (enterprise restrictions, an agent that only runs
shell commands), install `marionette_cli` and run its self-describing reference once
per session before driving anything:

```bash
dart pub global activate marionette_cli
marionette help-ai
```

That prints every command's syntax, expected output, and exit codes — treat it as the
authoritative low-level reference; everything in this skill's *What you can do* table
maps onto it one-for-one (`tap` ↔ `tap --key/--identifier/--text/--type/--x/--y`,
`get_interactive_elements` ↔ `get-interactive-elements`, etc.). Use `--uri <ws-uri>`
for one-off sessions and `register <name> <uri>` + `-i <name>` for repeated
interaction with the same app; `marionette doctor` checks connectivity of every
registered instance and `unregister` cleans up stale ones.

## Keeping this skill in sync

This file is meant to track releases, not just the version it was written against
(currently `0.6.0` across all three packages). When a tool or CLI command is
added, renamed, or changes behavior:

- Update the capability table and any affected practice/troubleshooting entry here.
- Cross-check against `marionette help-ai`'s own output — it is generated from the
  same command set and should never disagree with this file. If you find a command
  here that `help-ai` doesn't mention (or vice versa), one of the two is stale; fix
  both in the same change rather than picking one to trust going forward.
