---
name: marionette-flutter-drive-app
description: Set up and drive a running Flutter app (debug or profile) with Marionette — an AI agent's hands and eyes for the app. Covers adding marionette_flutter, MarionetteBinding, MarionetteConfiguration for custom widgets, a LogCollector, and MarionetteDeviceConfig — then tapping/typing/scrolling, screenshots, logs, hot reload/restart, device sweeps, and custom extensions, via marionette_mcp or the marionette CLI. Use whenever asked to test, click through, smoke-test, automate, QA, or interact with a Flutter app; when integrating marionette_flutter or registering a custom extension; after a feature or UI/design-system change; to reproduce or verify a bug; to walk a behaviour-neutral refactor; to sweep for accessibility; to exercise form validation; or to capture before/after evidence for a PR. Also load whenever a Marionette call fails, can't see a widget, reports not connected or a version mismatch, or hits a single-binding assertion. Not for CI suites, release builds, or performance work — see When not to use.
---

# marionette_flutter: drive an app

Marionette lets an AI agent drive a **running** Flutter app (debug or profile —
never release) the way a real user would: read the screen, tap, type, scroll,
screenshot, read logs, hot reload. It has two halves:

- **`marionette_flutter`** — the package you add to the app. It registers a VM
  service extension per action (`ext.flutter.marionette.*`).
- **The bridge** — either **`marionette_mcp`** (MCP tools, e.g. `connect`,
  `tap`, `get_interactive_elements`) or **`marionette_cli`** (shell commands,
  e.g. `marionette tap --key ...`). Nearly the same capabilities, different
  transport — the CLI additionally offers `record-video`, with no MCP
  equivalent (see the capability table, below). Prefer the MCP tools when
  they're in your tool list; fall back to the CLI in restricted environments
  (enterprise policy, a shell-only agent) — run `marionette help-ai` once at
  the start of such a session and follow its reference for exact syntax.

Everything shared between the two applies to either transport — action names
differ only in casing (`get_interactive_elements` vs
`get-interactive-elements`).

## Preparing the app

`connect` (or any CLI command) only works if the target app initialized
`MarionetteBinding`. If you're not sure whether it has, check `main.dart` (or
ask) — skip the rest of this section if it's already there and you just need
to drive the app, and jump to *When to use this*.

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

### Custom design system? Teach Marionette about it

Zero-config setup only recognizes stock Material widgets (`ElevatedButton`,
`TextField`, `Switch`, …) and extracts text only from `Text`, `RichText`,
`EditableText`, `TextField`, and `TextFormField`. If the app wraps its own
buttons, fields, or text — true of most production apps — `get_interactive_elements`
will look sparse and `tap(text: ...)` will fail to find things that are
clearly on screen. That's not a Marionette bug; it just doesn't know your
widget types yet:

```dart
MarionetteConfiguration(
  // Recognize your custom interactive widgets.
  isInteractiveWidget: (type) =>
      type == MyPrimaryButton || type == MyTextField,
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

`extractText` receives the `Element`, not just the `Widget`, so it can walk
the subtree when a label is itself a widget rather than a plain string.
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

One more `MarionetteConfiguration` field, `shouldStopTraversal`, is worth
naming only to warn against it: it's tempting to add a scroll container there
to "reduce traversal cost," but on a real production app that measurably
*dropped* widget coverage from 25.8% to 17.8% — the agent lost visibility into
everything nested below the cut, including the content it needed to reach.
Leave it `null` unless a profiler has shown a real, measured cost, and never
point it at a scrolling container.

### Logs for `get_logs`

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

### Screenshot size

`take_screenshots` downscales captures to fit within 2000×2000 physical
pixels by default, to keep base64 payloads manageable. Override
`maxScreenshotSize` on `MarionetteConfiguration` if a screen needs more
detail (`Size(3000, 3000)`, say), or set it to `null` to disable resizing
entirely — but keep the default unless there's a concrete reason to raise it,
since larger screenshots mean larger payloads on every call.

### Device-config sweeps

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

### The single-binding rule

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

### Version alignment

The MCP `connect` tool checks that `marionette_mcp` and the app's
`marionette_flutter` are on the same version, and fails with a clear message
rather than a confusing runtime error if they aren't. The CLI does not
perform this check — a stale `marionette_flutter` there can fail in less
obvious ways instead of a clear mismatch error. Either way, don't chase a
mismatch by retrying — align the versions: `flutter pub add marionette_flutter`
in the app, and `dart pub global activate marionette_mcp`/`marionette_cli`
for the bridge (or `dart pub add dev:marionette_mcp`/`dev:marionette_cli` if
you'd rather pin it as a dev dependency instead of a global tool).

## When to use this

Reach for Marionette any time the fastest way to know whether something works
is to actually run the app and look, rather than reason about the code:

- **After implementing a feature.** Connect, navigate to the new screen, and
  exercise the happy path — a working build isn't the same as a working
  feature.
- **After a UI or design-system change.** Confirm the affected screens still
  render and respond as expected, not just that the app compiles.
- **Reproducing a bug from a ticket.** Follow the reported steps, capture a
  screenshot and `get_logs` output as evidence the bug is real and what it
  looks like — before touching any code.
- **Verifying a bugfix.** Reproduce with the same steps, apply the fix,
  `hot_reload`, and replay those exact steps again to confirm the symptom is
  gone (not a different, adjacent symptom).
- **Walking a "behaviour-neutral" refactor.** Claims that a refactor changes
  nothing observable are exactly the claims worth checking — a quick
  regression walk of the touched screens catches what review alone misses.
- **An accessibility sweep.** Use `set_device_config` to try `text_scale`
  around 2.0–3.0 (real devices top out near 3.0) and `bold_text: true` on the
  screen in question, then check `get_logs` for overflow errors — that
  combination is where cramped layouts usually break first. (Needs the app to
  have opted in via `MarionetteDeviceConfig` — see *Device-config sweeps*.)
- **Form and validation work.** Enter deliberately invalid input and read the
  error strings back via `get_interactive_elements`/`take_screenshots` — it's
  the only way to confirm the *user-visible* message is right, not just that
  a validator returns an error code.
- **Evidence for a PR or ticket comment.** A quick before/after
  `take_screenshots` pair is often more convincing, and faster to produce,
  than a written description of a UI change. For a multi-step flow rather
  than a single static change, `record-video` (CLI-only, no MCP equivalent —
  see the capability table) captures the whole interaction as a short clip,
  which shows off a new feature or a fixed flow better than a screenshot
  pair can.

## When not to use this

- **CI or a repeatable regression suite.** Marionette's gestures are
  best-effort simulations of user input, not deterministic instrumentation —
  results can vary across platforms, custom widgets, and overlays. For a
  suite that needs to pass or fail the same way every time, use
  [Patrol](https://patrol.leancode.co) instead.
- **Release builds.** Not a limitation to work around — Marionette relies on
  the Dart VM Service, which doesn't exist in a release binary. Debug and
  profile only.
- **Performance work.** Marionette can *trigger* the interactions you want to
  profile, but measuring them is Flutter DevTools' job, not this one.

## Connecting

Every action needs a VM service WebSocket URI (`ws://127.0.0.1:PORT/TOKEN=/ws`)
— the developer running the app has it in their `flutter run` console output,
or in a DevTools link. Ask for it and pass it to `connect` (MCP) or `--uri` /
a registered `-i <name>` (CLI) before anything else.

If more than one running instance is already in play — several apps
registered with the CLI, or the user's message mentions more than one device
or simulator — don't guess which one to use. Either infer the right one from
what's already been said in the conversation (e.g. "the iOS one" when only one
registered instance is iOS), or ask which to target. Getting the wrong
instance is easy to miss until several steps later, so it's worth the one
question up front.

For the CLI, prefer `--uri` for a one-off session and
`marionette register <name> <uri>` + `-i <name>` when you'll issue many
commands against the same app in a row. When you're done for the session
(MCP), call `disconnect` — it's not required for correctness (a fresh
`connect` implicitly replaces it), but leaving a session dangling makes it
easy to act on a stale connection later without noticing.

Give `connect` a `session_title` (a short description of what you're
testing, e.g. `"profile validation"`) — it opens a session directory that
carries the run's step log and screenshots, and resuming it later (after a
compaction, an interruption, or a deliberate pause) is as simple as passing
the same title again. See *Reporting what you found* for what that directory
is for and what you're expected to do with it before disconnecting.

## What you can do once connected

| Category          | Actions                                                                                                      | Notes                                                                                                                                                                                                                                                                                                            |
|-------------------|--------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Inspection        | `get_interactive_elements`, `take_screenshots`, `get_logs`                                                   | `get_interactive_elements` is how you "see" the screen — call it before guessing at a target, and again after any navigation you didn't drive step by step. `take_screenshots` returns images inline by default; pass `inline: false` once a screenshot is evidence to cite rather than something you need to look at now — see *Reporting what you found*. `get_logs` needs a `LogCollector` wired up app-side (see *Logs for `get_logs`*, above); otherwise it returns setup instructions instead of an error. |
| Gestures          | `tap`, `secondary_tap`, `double_tap`, `long_press`, `swipe`, `pinch_zoom`, `scroll_to`, `press_back_button`  | Match by `key` › `identifier` › `text` › `type` › coordinates, in that preference order — see *Good practices*. `secondary_tap` is desktop-only.                                                                                                                                                                 |
| Text input        | `enter_text`, `press_key`                                                                                    | `enter_text` overwrites a field's value directly. `press_key` sends a real key event (submit on `enter`, shortcuts via `modifiers`) but only edits in-place on desktop/web — on mobile, field editing still needs `enter_text`.                                                                                  |
| Device config     | `set_device_config`                                                                                          | Sweeps text scale / bold text / light-dark under the app's *current* screen, without touching OS settings. Needs the app to opt in — see *Device-config sweeps*, above — otherwise it returns setup instructions rather than failing.                                                                            |
| Custom extensions | `list_custom_extensions`, `call_custom_extension`, plus any first-class tool an app registered with a schema | See *Custom extensions*, below.                                                                                                                                                                                                                                                                                  |
| Dev workflow      | `hot_reload`, `hot_restart`                                                                                  | `hot_reload` preserves state; use `hot_restart` only for changes a reload can't pick up (main()/bootstrap edits, global singletons, state shape) — requires the app to be running via `flutter run`.                                                                                                             |
| Session           | `connect`, `disconnect`                                                                                      | `connect` must be called before any other tool; a second `connect` implicitly disconnects the first. `connect` also opens (or resumes, via `session_title`) a session directory that owns the step log and screenshots — see *Reporting what you found*.                                                        |
| Video (CLI only)  | `record-video`                                                                                               | Records a WebM video of the session (`-o/--output`, `-d/--duration`, `--width`/`--height`; needs `ffmpeg` on `PATH`). No MCP equivalent — use `take_screenshots` there instead.                                                                                                                                  |

## Good practices

- **Look before you act.** Call `get_interactive_elements` (or
  `take_screenshots` for a visual check) before the first gesture on a new
  screen. Don't infer what's on screen from memory of the source code — the
  whole point of Marionette is to check the *running* state.
- **Selector priority: `key` > `identifier` > `text` > `type`/coordinates.**
  Keys (`ValueKey<String>`) and Semantics `identifier`s survive copy changes,
  localization, and refactors; `text` breaks the moment a label is edited or
  translated; coordinates break on any layout shift, font-scale change, or
  screen-size difference. Treat coordinates as a last-resort diagnostic, not
  the normal way to target something — if nothing else works, that's a sign
  the widget needs a key or `Semantics(identifier: ...)`, not a reason to keep
  using coordinates.
- **An element "not found" is usually a setup gap, not a bug.** Before
  concluding a widget can't be reached, suspect it's a custom widget type
  Marionette doesn't recognize yet, or custom-painted content with no
  `Semantics` annotation — both fixed under *Preparing the app*, above, not
  something to work around here.
- **If coverage looks low across a whole screen rather than one missing
  element, don't reach for `shouldStopTraversal`.** It's tempting to suggest
  filtering a scroll container out of traversal to "reduce noise," but that's
  the one config change measured to make things worse (25.8% → 17.8% widget
  coverage on a real app) — see *Custom design system?*, above.
- **Confirm side effects with `get_logs`, not just UI state.** A tap that
  looks like it worked isn't the same as the network call actually firing.
- **Give the app's flows explicit context.** Marionette can see the widget
  tree and act on it, but it has no idea what the product's flows, naming
  conventions, or edge cases are. State which screen to reach, the expected
  keys/labels, any precondition the flow assumes (e.g. "assume the user is
  already logged in"), and the interaction goal in one sentence, rather than
  assuming that's inferable from the UI alone.
- **Treat every gesture as best-effort.** Focus, text entry, and scrolling
  are simulations of user input and can behave differently across platforms,
  custom widgets, or overlays. A flow that's consistently flaky (not just
  occasionally) is a signal to expose a clearer key/identifier, flatten a
  deeply nested `GestureDetector` hit target, or extend
  `MarionetteConfiguration` — not to retry harder.

## Reporting what you found

`connect` opens (or resumes) a session directory under
`.marionette/sessions/` — the server's own record of the run, kept separate
from your own context so it survives a compaction or an interruption.
`disconnect`'s response repeats that directory's path with a reminder to
write `report.md`: treat that as a requirement, not a suggestion — it's the
enforcement mechanism precisely because an instruction here, on its own,
gets skipped.

Two files in that directory are appended by the server, not you — don't
write to them yourself:

- **`steps.md`** — one line per tool call: the tool, a short selector, and
  the outcome. No payloads (`enter_text` values are redacted).
- **`screenshots/`** — populated only when you call `take_screenshots` with
  `inline: false`, which is what you want once a screenshot is evidence
  you're citing rather than something you need to look at right now (each
  inline image costs real visual tokens).

You own two more files there, which the server never writes:

- **`report.md`** — written once, at the end, from your own context, not by
  re-reading `report-full.md`. Write it on either of two triggers: the run
  completed, or you're stopping early (a blocking failure, a budget/time
  limit, an ambiguous requirement you can't resolve alone). An interrupted
  run's report states *why* it stopped and what was left untested, instead
  of silently reporting only what got covered.
- **`report-full.md`** — a working log, appended *during* a longer run at
  moments that matter (a check starts, an observation lands, a finding
  appears) — not one entry per tap. Skip it for a short run: a single-screen
  check that finishes in one pass just writes `report.md` directly, nothing
  else materializes. It exists so a run survives a compaction, an
  interruption, or an explicit resume (`connect` again with the same
  `session_title`) — read it back only in those cases, to recover context
  you'd otherwise lose, never as a matter of course before writing
  `report.md`.

### The report contract

- **The `Tested:` line is rendered from `steps.md`, never from memory or
  your own sense of what you did.** This is the anti-overstatement mechanism
  — read the step count and the actions taken back out of the file the
  server wrote, don't estimate.
- **Every finding cites evidence** — a step, a `get_logs` line, or a
  screenshot path. No evidence means it's a suspicion, not a finding: say so
  explicitly rather than upgrading a hunch.
- **Under six lines per finding, no prose paragraphs.** A severity tag,
  one-line summary, a repro path, and the evidence citation — that's the
  shape; if it doesn't fit, cut the finding down rather than making room.
- **The chat message after disconnecting is a TL;DR derived from
  `report.md`**, not a separate narrative composed from scratch.

Two shapes — an app with findings, and a clean run:

```
Marionette report — 2 findings · User Profile
Tested: profile view, edit form, save flow (14 steps, 3 screenshots)

1. [bug] Date of birth accepts future dates — no validation
   Repro: Profile → Edit → DOB = 2099-01-01 → Save
   Evidence: step 9, log "saved dob=2099-01-01"

2. [bug] Save does not persist — changes lost after restart
   Repro: Profile → Edit → Name = "X" → Save → hot_restart → Profile
   Evidence: step 14, screenshots/02-after-restart.png
```

```
Marionette report — no issues · Checkout
Tested: cart, address form, payment, confirmation (18 steps)
Checks: field validation, back navigation, dark mode, text scale 2.0
```

`.marionette/` is gitignored by default. Committing a session directory —
attaching a report to a PR, say — is a deliberate choice you make
explicitly, never something to do as a matter of course.

## Custom extensions

Apps can expose their own actions via `registerMarionetteExtension` (route
navigation, seeding test data, feature-flag toggles — anything the generic
tools can't express). Call `list_custom_extensions` before assuming an action
isn't possible. Extensions that declare a scalar `inputSchema` show up as
first-class, individually named tools (sanitized to `[a-z0-9_-]`, e.g.
`appNavigation.goToPage` → `app_navigation_go_to_page`) with validated
arguments; schema-less ones are only reachable through the generic
`call_custom_extension`, passing the *real* (unsanitized) name and key-value
args.

## Troubleshooting

| Symptom                                                                                            | Likely cause                                                                      | Fix                                                      |
|----------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|----------------------------------------------------------|
| "Not connected to any app"                                                                         | No successful `connect` yet in this session                                       | `connect` before anything else — see *Connecting*, above |
| MCP `connect` fails with a version mismatch                                                        | `marionette_mcp` and `marionette_flutter` are different versions (the CLI doesn't check this) | See *Version alignment*, above                           |
| Custom buttons/fields don't show up, or `tap(text:)`/`scroll_to(text:)` can't find a visible label | Widget type or text isn't recognized                                              | See *Custom design system?*, above                       |
| `get_logs` says no collector configured                                                            | No `LogCollector` wired up                                                        | See *Logs for `get_logs`*, above                         |
| `set_device_config` returns setup instructions instead of succeeding                               | App hasn't opted in                                                               | See *Device-config sweeps*, above, then hot restart      |
| Binding assertion error on startup (often under `flutter test`)                                    | Two `WidgetsBinding`s initialized                                                 | See *The single-binding rule*, above                     |
| Session directory lands somewhere unexpected (e.g. not the project root)                           | No `MARIONETTE_SESSION_DIR` set and the server's own working directory isn't reliably the repo root | Pass `session_dir` to `connect` (`--session-dir` on the CLI) explicitly — see *Reporting what you found*, above |
| Nothing above applies, and it's a release build                                                    | Marionette needs the VM Service                                                   | Not supported by design — see *When not to use*          |

## CLI fallback

When MCP tools aren't available, install `marionette_cli` and run its
self-describing reference once per session before driving anything:

```bash
dart pub global activate marionette_cli
marionette help-ai
```

That prints every command's syntax, expected output, and exit codes — treat
it as the authoritative low-level reference; everything in the capability
table above maps onto it one-for-one (`tap` ↔
`tap --key/--identifier/--text/--type/--x/--y`, `get_interactive_elements` ↔
`get-interactive-elements`, etc.), plus `record-video`, which only exists on
this side. Use `--uri <ws-uri>` for a one-off session
and `register <name> <uri>` + `-i <name>` for repeated interaction with the
same app; `marionette doctor` checks connectivity of every registered
instance and `unregister` cleans up stale ones. Session reports work the same
way here: pass `--session <title>` (the CLI's equivalent of `session_title`)
consistently across a script's invocations to log a multi-step run into one
session directory instead of a fresh, untitled one per command — see
*Reporting what you found*, above.

## Keeping this skill in sync

This file must track the package release it ships with, and the
capability table above should never disagree with `marionette help-ai`'s own
output — both are generated from the same command set. If a tool or CLI
command is added, renamed, or changes behavior, update the table and any
affected practice/troubleshooting entry, and check `marionette help-ai`
alongside it: if one mentions a command the other doesn't, fix both together
rather than picking one to trust going forward.
