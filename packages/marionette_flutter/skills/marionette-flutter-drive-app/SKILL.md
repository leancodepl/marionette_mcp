---
name: marionette-flutter-drive-app
description: Drive a running Flutter app (debug or profile) with Marionette — an AI agent's hands and eyes for the app — tapping/typing/scrolling, screenshots, logs, hot reload/restart, device sweeps, custom extensions, and the session report, via marionette_mcp or the marionette CLI. Use whenever asked to test, click through, smoke-test, automate, QA, or interact with a Flutter app; after a feature or UI/design-system change; to reproduce or verify a bug; to walk a behaviour-neutral refactor; to sweep for accessibility; to exercise form validation; to call or register a custom extension; or to capture before/after evidence for a PR. Also load whenever a Marionette call fails or reports not connected, and for permission dialogs and other system UI via the native lane. If the app has no MarionetteBinding yet, connect reports a version mismatch, startup hits a binding assertion or hangs, or Marionette can't see the app's custom widgets, use marionette-flutter-setup. Not for CI suites, release builds, or performance work.
---

# marionette_flutter: drive an app

Marionette lets an AI agent drive a **running** Flutter app (debug or profile —
never release) the way a real user would: read the screen, tap, type, scroll,
screenshot, read logs, hot reload. It has two halves:

- **`marionette_flutter`** — the package in the app. It registers a VM service
  extension per action (`ext.flutter.marionette.*`).
- **The bridge** — **`marionette_mcp`** (MCP tools, e.g. `connect`, `tap`,
  `get_interactive_elements`) or **`marionette_cli`** (shell commands, e.g.
  `marionette tap --key ...`). Nearly the same capabilities; the CLI adds
  `record-video`. Prefer the MCP tools when they're in your tool list; fall
  back to the CLI in restricted environments (enterprise policy, a shell-only
  agent) — see *CLI fallback*. Everything below applies to both; action names
  differ only in casing (`get_interactive_elements` vs
  `get-interactive-elements`).

## Before you start

`connect` (or any CLI command) only works if the app initialized
`MarionetteBinding`; if unsure, check `main.dart` (or ask). If it hasn't, or
the agent can't see the app's own buttons and fields, set the app up first with
`marionette-flutter-setup` (binding, the `material_ui` and `cupertino_ui`
integrations, custom design system, `LogCollector`,
`MarionetteDeviceConfig`, the single-binding rule, version alignment). If that
skill is not installed, run `dart run skills@ get -s marionette-flutter-setup`,
or follow https://marionette.leancode.co/docs/configure/.

Before each control or QA session, also when the binding is already there,
run *Check the source first* and *Verify* in `marionette-flutter-setup`, and
pass the result to `connect` as `required_ui_libraries`.

## When to use this

Whenever the fastest way to know whether something works is to run the app and
look, rather than reason about the code:

- **After implementing a feature.** Connect, navigate to the new screen, and
  exercise the happy path — a working build isn't a working feature.
- **After a UI or design-system change.** Confirm the affected screens still
  render and respond, not just that the app compiles.
- **Reproducing a bug from a ticket.** Follow the reported steps and capture a
  screenshot and `get_logs` output as evidence — before touching any code.
- **Verifying a bugfix.** Reproduce, apply the fix, `hot_reload`, and replay
  those exact steps to confirm the symptom is gone (not a different, adjacent
  one).
- **Walking a "behaviour-neutral" refactor.** A quick regression walk of the
  touched screens catches what review alone misses.
- **An accessibility sweep.** `set_device_config` with `text_scale` around
  2.0–3.0 (real devices top out near 3.0) and `bold_text: true`, then check
  `get_logs` for overflow errors — where cramped layouts break first. (Needs
  the app's `MarionetteDeviceConfig` opt-in — see `marionette-flutter-setup`.)
- **Form and validation work.** Enter invalid input and read the error strings
  back via `get_interactive_elements`/`take_screenshots` — the only way to
  confirm the *user-visible* message, not just a validator's error code.
- **Evidence for a PR or ticket.** A before/after `take_screenshots` pair is
  often faster and more convincing than a written description. For a
  multi-step flow, `record-video` (CLI only) captures the whole interaction.

## When not to use this

- **CI or a repeatable regression suite.** Marionette's gestures are
  best-effort simulations of user input, not deterministic instrumentation —
  results vary across platforms, custom widgets, and overlays. Use
  [Patrol](https://patrol.leancode.co) instead; `marionette-flutter-to-patrol`
  turns a verified run into Patrol tests.
- **Release builds.** Marionette relies on the Dart VM Service, which doesn't
  exist in a release binary. Debug and profile only.
- **Performance work.** Marionette can *trigger* the interactions; measuring
  them is Flutter DevTools' job.

## Connecting

Every action needs a VM service WebSocket URI (`ws://127.0.0.1:PORT/TOKEN=/ws`).
Pass it to `connect` (MCP) or `--uri` / a registered `-i <name>` (CLI) first:

- **The developer runs the app.** The URI is in their `flutter run` output or
  a DevTools link. Ask for it.
- **You run the app.** Start `flutter run` yourself, in the background, on the
  device the developer wants. It prints `A Dart VM Service on <device> is
  available at: http://127.0.0.1:PORT/TOKEN=/`; the URI is that address as
  `ws://127.0.0.1:PORT/TOKEN=/ws` (the DevTools line's `uri=` parameter carries
  the same value). `hot_reload` and `hot_restart` then act on your own run.

If more than one running instance is in play — several apps registered with
the CLI, or the user mentions more than one device or simulator — don't guess.
Infer the right one from the conversation (e.g. "the iOS one" when only one
registered instance is iOS), or ask: the wrong instance is easy to miss until
several steps later.

For the CLI, use `--uri` for a one-off session and
`marionette register <name> <uri>` + `-i <name>` for many commands against the
same app. When done (MCP), call `disconnect` — a fresh `connect` replaces it
anyway, but a dangling session makes it easy to act on a stale connection.

Give `connect` a `session_title` — a short description of what you're testing,
e.g. `"profile validation"`, under ~60 characters (longer is truncated), and
**always in English**, whatever the prompt's language: it is slugified into the
session directory's name, which should stay predictable. If the app enables
session reports (`MarionetteConfiguration(enableSessionReports: true)`), it
opens a fresh session directory for this run's step log and screenshots. One
run is one directory: there's no resuming, and the same title on a later
`connect` opens another directory. A run interrupted partway (a compaction, a
dropped connection) is abandoned; don't pick it up or reuse its title. See
*Reporting what you found*.

## What you can do once connected

| Category          | Actions                                                                                                      | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
|-------------------|--------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Inspection        | `get_interactive_elements`, `take_screenshots`, `get_logs`                                                   | `get_interactive_elements` is how you "see" the screen — call it before guessing at a target, and again after any navigation you didn't drive step by step. `take_screenshots` returns images inline by default; pass `inline: false` once a screenshot is evidence to cite rather than something you need to look at now — see *Reporting what you found*. `get_logs` needs a `LogCollector` wired up app-side (see `marionette-flutter-setup`); otherwise it returns setup instructions instead of an error. On a screen that repeats the same subtree, pass `ancestor_keys` to list just one copy of it (see *Repeated keys*, below).   |
| Gestures          | `tap`, `secondary_tap`, `double_tap`, `long_press`, `swipe`, `pinch_zoom`, `scroll_to`, `press_back_button`  | Match by `key` › `identifier` › `text` › `type` › coordinates, in that preference order — see *Good practices*. When the same key repeats in several identical subtrees, add `ancestor_keys` — see *Repeated keys*, below. `secondary_tap` is desktop-only.                                                                                                                                                                                                                                                                                                                                                                                |
| Text input        | `enter_text`, `press_key`                                                                                    | `enter_text` overwrites a field's value directly, and takes `ancestor_keys` like the gestures do. `press_key` sends a real key event (submit on `enter`, shortcuts via `modifiers`) but only edits in-place on desktop/web — on mobile, field editing still needs `enter_text`.                                                                                                                                                                                                                                                                                                                                                            |
| Device config     | `set_device_config`                                                                                          | Sweeps text scale / bold text / light-dark under the app's *current* screen, without touching OS settings. Needs the app to opt in — see `marionette-flutter-setup` — otherwise it returns setup instructions rather than failing.                                                                                                                                                                                                                                                                                                                                                                                                         |
| Custom extensions | `list_custom_extensions`, `call_custom_extension`, plus any first-class tool an app registered with a schema | See *Custom extensions*, below.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Dev workflow      | `hot_reload`, `hot_restart`                                                                                  | `hot_reload` preserves state; use `hot_restart` only for changes a reload can't pick up (main()/bootstrap edits, global singletons, state shape) — requires the app to be running via `flutter run`.                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Session           | `connect`, `disconnect`                                                                                      | `connect` must be called before any other tool; a second `connect` implicitly disconnects the first. `connect` also opens a fresh session directory (`session_title`) that owns the step log and screenshots — see *Reporting what you found*.                                                                                                                                                                                                                                                                                                                                                                                             |
| Native lane       | `native_connect`, `native_disconnect`, `native_get_elements`, `native_wait_for`, `native_tap`, `native_enter_text`, `native_scroll`, `native_swipe`, `native_press_key`, `native_hide_keyboard`, `native_take_screenshot`, `native_notifications` | System UI outside the Flutter tree. Needs its own `native_connect` — see *System UI outside Flutter*, below. |
| Video (CLI only)  | `record-video`                                                                                               | Records a WebM video of the session (`-o/--output`, `-d/--duration`, `--width`/`--height`; needs `ffmpeg` on `PATH`). No MCP equivalent — use `take_screenshots` there instead.                                                                                                                                                                                                                                                                                                                                                                                                                                                            |

## Good practices

- **Look before you act.** Call `get_interactive_elements` (or
  `take_screenshots`) before the first gesture on a new screen; don't infer the
  screen from memory of the source. The listing is compact by default: it
  drops rendering details and reports `visible` only when an element is not
  visible. Pass `compaction: "none"` (`--compaction=none`) for the full dump.
- **Selector priority: `key` > `identifier` > `text` > `type`/coordinates.**
  Keys (`ValueKey<String>`) and Semantics `identifier`s survive copy changes,
  localization and refactors; `text` breaks when a label is edited or
  translated; coordinates break on any layout shift, font scale or screen size.
  Coordinates are a last-resort diagnostic: needing them means the widget
  needs a key or `Semantics(identifier: ...)`.
- **Discovery text is not always a selector.** A button or list tile reports
  the labels of its children as its `text`. When that text joins several
  labels (`"Accept terms\nRequired"`), comes from a `Semantics` label (an
  icon's `semanticLabel`), or includes the content of a `WidgetSpan`
  (`"Hi Bob"` from `Text.rich` with `WidgetSpan(child: Text("Bob"))`),
  `tap(text:)` does not match it: use the key, the identifier, the text of
  one visible `Text`, or coordinates. The listing prints a line break as
  `\n`, a carriage return as `\r` and a backslash as `\\`; unescape a copied
  value before you pass it back.
- **Repeated keys: scope the match with `ancestor_keys`.** Every tool takes the
  first match, so on a screen that repeats a subtree (grid cells, repeated
  cards, a dev screen embedding several copies of the app) a plain
  `tap(key: "cell.joinButton")` always hits the first copy. Pass the wrapper
  keys, outermost first:
  `{"key": "cell.joinButton", "ancestor_keys": ["session_2", "grid.cell_3"]}`.
  Each key is looked up strictly *inside* the previous one (so `grid.cell_3`
  may repeat in every session), and the target must be inside the last. If the
  wrapper repeats too, go one level up.
  - **Finding the chain:** `get_interactive_elements` is a flat list in tree
    order, so a listed keyed wrapper appears just before its elements. A
    wrapper whose centre catches no hit test isn't listed: read its key from
    the source or ask. Confirm a chain with
    `get_interactive_elements(ancestor_keys: [...])`: a scope alone is enough
    there, the wrapper itself is listed, and a wrong key fails by name.
  - **A key with no element fails the call**, naming it and where it was
    looked for (`Scope element with key "grid.cell_9" (ancestor_keys[1]) not
    found inside "session_2"`). It never widens the search to the whole
    screen, so a typo can't act on the wrong copy.
  - **`scroll_to` works into lazy lists:** a scope not built yet (e.g.
    `ancestor_keys: ["row_20"]` in a long `ListView`) is looked for again after
    every drag, and the scrolling list may be inside the scope or above it. A
    scope key that exists nowhere is reported after the list is scanned.
  - `coordinates` and `focused_element` ignore `ancestor_keys`, and a scope
    alone is not a selector for the gesture tools.
  - Prefer this over coordinates or indices baked into keys: the chain
    survives layout changes and keeps production keys clean.
- **An element "not found" is usually a setup gap, not a bug.** Suspect a
  custom widget type Marionette doesn't recognize yet, or custom-painted
  content with no `Semantics` — both fixed in `marionette-flutter-setup`.
- **Low coverage across a whole screen? Don't reach for
  `shouldStopTraversalAtElement`.** Filtering a scroll container out of
  traversal is the one change measured to make things worse (25.8% → 17.8%
  widget coverage on a real app) — see `marionette-flutter-setup`.
- **Confirm side effects with `get_logs`, not just UI state.** A tap that looks
  like it worked isn't the network call actually firing.
- **Give the app's flows explicit context.** Marionette sees the widget tree,
  not the product's flows, naming or edge cases. State the screen to reach,
  the expected keys/labels, any precondition (e.g. "assume the user is already
  logged in"), and the goal in one sentence.
- **Treat every gesture as best-effort.** Focus, text entry and scrolling are
  simulations and can differ across platforms, custom widgets, or overlays. A
  consistently flaky flow is a signal to expose a clearer key/identifier,
  flatten a deeply nested `GestureDetector` hit target, or extend
  `MarionetteConfiguration` — not to retry harder.

## System UI outside Flutter: the native lane

The Flutter lane sees only the widget tree. Permission dialogs, system alerts,
pickers and share sheets, WebView content, native views and screens, and
notifications go through the **native lane** (`native_*` tools, `native-*` CLI
commands), which drives the device's own UI automation server. While system UI
is open, `get_interactive_elements` still lists the Flutter widgets underneath,
and a tap on them does nothing. Switch to the native lane whenever the target
isn't in the Flutter tree, and back as soon as the app is in front: in-app
widgets are always better driven by the Flutter lane. It needs its own
`native_connect`, and its coordinates are screen pixels, never Flutter ones.
It runs on macOS and Linux hosts, on Android devices and emulators and one iOS
Simulator at a time, with one client per device. Before the first native call,
read [references/native-lane.md](references/native-lane.md).

## Reporting what you found

This applies only when `connect`'s response actually includes an
`Opened session:` path — check the real response. It is missing when the app
never enabled session reports (`MarionetteConfiguration(enableSessionReports:
true)`; don't turn that on yourself unless the user asks for a report), or when
the directory couldn't be created (the response says so, e.g. "Could not open a
session directory, so this run will not be logged"). Then there's no
`steps.md` and nowhere to write `report.md` — see the last rule of *The report
contract*.

`connect` opens a fresh session directory under `.marionette/sessions/` — the
server's own record of the run, separate from your context. `disconnect`'s
response repeats its path with a reminder to write `report.md`: treat that as a
requirement — it exists because an instruction here, alone, gets skipped.

The server appends two things there; don't write to them yourself:

- **`steps.md`** — one line per tool call: the tool, a short selector, and the
  outcome. No payloads (`enter_text` values are redacted).
- **`screenshots/`** — filled only by `take_screenshots` with `inline: false`,
  which you want once a screenshot is evidence you're citing rather than
  something to look at now (each inline image costs real visual tokens).

You own **`report.md`**, which the server never writes. Write it once, at the
end, from your own context, when the run completed or when you stop early (a
blocking failure, a budget/time limit, an ambiguous requirement you can't
resolve alone). A report for a run stopped early states *why* it stopped and
what was left untested — there's no resuming, so it is the only record. Before
drafting a single line, name the report language explicitly: the language of
the prompt that started this session (the message that led to the first
`connect`) — not English by default, not the app's UI language, not your own
narration's language. Doing this as a deliberate step is what prevents
defaulting to English.

### The report contract

- **Write `report.md` — and the chat message — in the language of the prompt
  that started the run.** Tool names, file paths (`report.md`, `steps.md`,
  `screenshots/01.png`) and widget keys/identifiers (`login_emailTextField`)
  are never translated. `session_title` is the one exception the other way:
  always English (see *Connecting*).
- **The `Tested:` line is rendered from `steps.md`, never from memory or your
  own sense of what you did.** This is the anti-overstatement mechanism — read
  the step count and the actions back out of the file the server wrote.
- **Every finding cites evidence** — a step, a `get_logs` line, or a
  screenshot path. No evidence means a suspicion, not a finding: say so rather
  than upgrading a hunch.
- **Under six lines per finding, no prose paragraphs.** A severity tag, a
  one-line summary, a repro path, and the evidence citation; if it doesn't
  fit, cut the finding down.
- **Prefix the headline and every finding with a status icon**, so severity
  is scannable: `✅` clean (no findings), `⚠️` only suspicions, `🐛` at least
  one confirmed bug — on the headline, the worst severity present; on a
  finding, its own. `➖` marks something explicitly skipped (a `Not covered:`
  line, or a check you didn't run). Icons decorate the tags/wording —
  `[bug]`, `[suspicion]`, `Not covered:` — never replace them, so the report
  still greps cleanly and reads fine where emoji don't render.
- **The chat message after disconnecting follows a fixed, compact template
  — not free-form prose, and not a second copy of `report.md`:**

  ```
  Marionette · <flow/feature> — <VERDICT>: <reason, a few words>
  ✓ <what worked, comma-separated>
  ✗ [<type>] <finding, one line>       (up to 5; beyond that: "+N more in report.md")
  ∅ Not covered: <what> — <why>
  → <session path>/report.md · <N> steps, <M> screenshots
  ```

  `<VERDICT>` is a fixed vocabulary, never translated: `PASS` (nothing found,
  full coverage), `SUSPECT` (only suspicions), `FAIL` (at least one confirmed
  bug), `BLOCKED` (coverage cut short by something that stopped you — bad test
  data, a stuck flow, a missing prerequisite; use it over `FAIL`/`PASS` when
  *that's* the story, even if you also found a bug). Each `✗` line's `[type]`
  is `bug`, `blocker`, `ux` (each matching a `[bug]` finding in `report.md`,
  evidence-backed) or `suspicion` (matching a `[suspicion]` one). Beyond the
  headline and the `→` line, rows are optional: skip `✓` if nothing worked,
  skip `✗`/`∅` for a `PASS`. The `→` line's counts come from `steps.md`, like
  `Tested:`. The chat message uses plain `✓`/`✗`/`∅`/`→` because it prints as
  raw terminal text, where emoji render at inconsistent widths; `report.md`
  is opened in an editor or on GitHub, where the colored `✅`/`⚠️`/`🐛`/`➖`
  render cleanly. Don't mix the two sets.
- **No session directory (see *Reporting what you found*)? There's no
  `report.md` and no contract to follow** — give the same chat message anyway
  (verdict, `✓`/`✗`/`∅` lines), drop the `→` line, and don't invent a
  `Tested:`-style step count: there's no `steps.md` to render it from.

This is what `report.md` looks like (in English here; write yours in the
prompt's language) — a confirmed bug, a clean run, then a suspicion:

```
🐛 Marionette report — 2 findings · User Profile
Tested: profile view, edit form, save flow (14 steps, 3 screenshots)

1. 🐛 [bug] Date of birth accepts future dates — no validation
   Repro: Profile → Edit → DOB = 2099-01-01 → Save
   Evidence: step 9, log "saved dob=2099-01-01"

2. 🐛 [bug] Save does not persist — changes lost after restart
   Repro: Profile → Edit → Name = "X" → Save → hot_restart → Profile
   Evidence: step 14, screenshots/02-after-restart.png
```

```
✅ Marionette report — no issues · Checkout
Tested: cart, address form, payment, confirmation (18 steps)
Checks: field validation, back navigation, dark mode, text scale 2.0
```

```
⚠️ Marionette report — no confirmed issues, 1 suspicion · Settings
Tested: notification toggles, language picker, theme toggle (9 steps, 2 screenshots)

1. ⚠️ [suspicion] Dark mode toggle reverts to light after hot_restart
   Repro: Settings → enable Dark mode → hot_restart → Settings
   Evidence: screenshots/02-after-restart.png shows light theme again

➖ Not covered: account deletion, data export — out of scope for this run
```

The chat message for the first run, and for a `BLOCKED` one — denser than
`report.md`'s headline, with a verdict word, since it stands alone:

```
Marionette · User Profile — FAIL: 2 bugs
✓ Profile view, edit form
✗ [bug] Date of birth accepts future dates — no validation
✗ [bug] Save does not persist — changes lost after restart
→ .marionette/sessions/user-profile-20260922T1412/report.md · 14 steps, 3 screenshots
```

```
Marionette · Password reset — BLOCKED: reset email never arrives
✓ Request form, validation messages
✗ [blocker] "Send reset link" succeeds but no email logged or received after 3 attempts
∅ Not covered: setting a new password, confirmation screen — flow can't proceed past the email step
→ .marionette/sessions/password-reset-20260922T1601/report.md · 11 steps, 1 screenshot
```

`.marionette/` is gitignored by default (the server writes that `.gitignore`
the first time it creates a session). Committing a session directory — to
attach a report to a PR, say — is a deliberate, explicit choice, never routine.

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

| Symptom                                                                                            | Likely cause                                                                                        | Fix                                                                                                                              |
|----------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| "Not connected to any app"                                                                         | No successful `connect` yet in this session                                                         | `connect` before anything else — see *Connecting*, above                                                                         |
| MCP `connect` fails with a version mismatch                                                        | `marionette_mcp` and `marionette_flutter` are different versions (the CLI doesn't check this)       | See *Version alignment* in `marionette-flutter-setup`                                                                            |
| Custom buttons/fields don't show up, or `tap(text:)`/`scroll_to(text:)` can't find a visible label | Widget type or text isn't recognized                                                                | See *Custom design system?* in `marionette-flutter-setup`                                                                        |
| A gesture or `enter_text` hits the wrong copy of a repeated widget                                 | The key repeats across identical subtrees; the first match wins                                     | Add `ancestor_keys` — see *Repeated keys*, above                                                                                 |
| `Scope element with key "…" (ancestor_keys[N]) not found`                                          | That wrapper key is misspelled, not built yet, or not inside the previous one                       | Check with `get_interactive_elements(ancestor_keys: [...])`; off-screen rows need `scroll_to` first — see *Repeated keys*, above |
| `get_logs` says no collector configured                                                            | No `LogCollector` wired up                                                                          | See *Logs for `get_logs`* in `marionette-flutter-setup`                                                                          |
| `set_device_config` returns setup instructions instead of succeeding                               | App hasn't opted in                                                                                 | See *Device-config sweeps* in `marionette-flutter-setup`, then hot restart                                                       |
| Binding assertion error on startup (often under `flutter test`)                                    | Two `WidgetsBinding`s initialized                                                                   | See *The single-binding rule* in `marionette-flutter-setup`                                                                      |
| `connect` reports `UI integrations: missing …`                                                     | The source uses `material_ui` or `cupertino_ui`, and the configuration lacks its integration        | Add what it names, then hot restart — see *Apps on `material_ui` or `cupertino_ui`* in `marionette-flutter-setup`                |
| `connect` reports `UI integrations: unverified …`                                                  | No `required_ui_libraries` given, so a loaded library may come from a dependency                    | Check the app's source imports, then `connect` again with them — see *Before you start*, above                                   |
| Session directory lands somewhere unexpected (e.g. not the project root)                           | No `MARIONETTE_SESSION_DIR` set and the server's own working directory isn't reliably the repo root | Pass `session_dir` to `connect` (`--session-dir` on the CLI) explicitly — see *Reporting what you found*, above                  |
| A Flutter tap does nothing while a dialog, sheet or picker is open                                 | System UI covers the app; the Flutter tree still lists the widgets underneath                       | Switch to the native lane — see *System UI outside Flutter*, above                                                               |
| Nothing above applies, and it's a release build                                                    | Marionette needs the VM Service                                                                     | Not supported by design — see *When not to use*                                                                                  |

## CLI fallback

When MCP tools aren't available, install `marionette_cli` and run its
self-describing reference once per session before driving anything:

```bash
dart pub global activate marionette_cli
marionette help-ai
```

It prints every command's syntax, output, and exit codes — the authoritative
low-level reference. The capability table maps onto it one-for-one (`tap` ↔
`tap --key/--identifier/--text/--type/--x/--y`, `get_interactive_elements` ↔
`get-interactive-elements`, etc.), except the app's custom extensions
(`list_custom_extensions`, `call_custom_extension` and the named tools built
from their schemas), which only the MCP server offers; `record-video` exists
only here. `ancestor_keys` is `--ancestor-keys`, repeated once per key,
outermost first:
`tap --key cell.joinButton --ancestor-keys session_2 --ancestor-keys grid.cell_3`.
`marionette doctor` checks every registered instance and `unregister` cleans up
stale ones; `marionette -i <name> doctor --required-ui-library <library>`
checks one app's UI integrations against the libraries its source uses. Session reports work here too, but every CLI invocation is its own
process with its own session directory: `--session <title>` (the CLI's
`session_title`) names it and doesn't join invocations into one run, so a
multi-step CLI run leaves one directory per command, where the MCP server keeps
one per connection. The native `native-*` commands are in the native-lane
reference.

## Keeping this skill in sync

This file, `references/native-lane.md`, `marionette-flutter-setup` and
`marionette-flutter-to-patrol` track the package release they ship with: setup
follows the `MarionetteConfiguration` API, and to-patrol reads the `steps.md`
format and *The report contract*, so a change to either updates it too. The
capability table must never disagree with `marionette help-ai` — both come from
the same command set. When a tool or CLI command is added, renamed, or changes
behavior, update the table, any affected practice/troubleshooting entry and
`marionette help-ai` together, rather than picking one to trust.
