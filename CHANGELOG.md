# Unreleased

- `get_interactive_elements` (and `marionette get-interactive-elements`) warns when the app is not in front — a dialog, the notification shade, a biometric prompt, a browser or another screen covers it; `marionette_flutter` reports the app lifecycle state with the elements
- Native lane: errors from `native_connect` and the `native_*` tools now name the failing stage (iOS bootstrap included) and end with a `Hint:` describing how to fix it
- Native lane: fix `foregroundApp` in `native_get_elements` always being `null` on Android 10+
- Native lane: decode numeric character references (e.g. `&#10;`) in native element text, so multi-line labels can be matched by `native_tap` / `native_enter_text`
- **Breaking (native lane):** element-targeting tools (`native_tap`, `native_enter_text`, `native_scroll`) share one selector — `text` (`label` in `native_enter_text`), `textContains`, `id`, `type`, `index`. When a selector matches several elements and clickable ones do not narrow it to one, the tool fails and lists the candidates instead of acting on the first match; pass `index` or a more specific selector
- **Breaking (native lane, iOS):** all native coordinates — `bounds` and `x`/`y`/`startX`/`startY`/`distance` — are screenshot pixels on every platform; on iOS they were WebDriverAgent points
- Native lane: tap and type into exactly the element the selector chose (iOS no longer re-locates it by accessibility id, which could hit another element with the same id)
- Native lane: `native_scroll` uses the real screen size instead of inferring it from element bounds
- Native lane (Android): an empty text field is identified by its hint (placeholder) text; (iOS) software keyboard keys are reported as clickable
- Native lane: add `native_press_key` (back, home, enter, backspace, tab, recents, volume_up, volume_down) and `native_hide_keyboard`; `native_enter_text` types into the focused field when no selector is given and accepts `clear`
- Native lane (iOS): `native_connect` with the `udid` of a simulator that is not booted now fails immediately with a hint, instead of `xcodebuild` silently booting it headless
- Native lane: `native_get_elements` reports element state — `value` (text field content), `enabled`, `focused` (Android), `checked`, `selected`, `scrollable` — only when it carries information, and accepts filters (`text`, `textContains`, `id`, `type`, `clickableOnly`, `includeForegroundApp`). On iOS the typed content of a Flutter field is now visible
- **Breaking (native lane, Android):** a filled text field keeps its label (hint) as `text`; its content moved to `value`, matching iOS. Selectors by label keep finding the field after typing
- Native lane: add `native_wait_for` (visible / gone with timeout) and `native_swipe` (start and end coordinates)
- Native lane: `native_scroll` can swipe inside a container (`within`), takes `maxSwipes`, stops at the end of the content, ignores off-screen (zero-size) matches, and searches with slow drags that do not fling past the target
- Native lane (Android): reads of the UI tree no longer take 10 s on screens with continuous animation (video, maps) — UIAutomator2's idle wait is lowered to 500 ms
- Native lane (iOS): elements scrolled out of view (e.g. a WebView's whole page) are no longer listed or matched, and partly visible ones are clipped to the screen so their center can be tapped
- Native lane: `native_scroll` no longer reports the end of the content while crossing a large uniform area (it needs two swipes without a visible change); `native_wait_for` never runs past `timeoutMs` when a tree read is slow
- Fix: the stdio server exits on stdin EOF while connected to an app (the VM service connection kept the process alive)
- Native lane (Android): tree reads no longer fail while a toast is shown — they wait until it disappears (up to 5 s), then fail with a hint to use `native_take_screenshot`; where UIAutomator2 reports the toast (e.g. API 28) it is listed read-only by `native_get_elements` and `native_wait_for`
- Native lane (Android): `native_hide_keyboard` no longer presses Back when only Gboard's floating toolbar is shown (hardware keyboard attached) — Back closed the current screen; it fails with a hint instead
- Native lane (iOS): identical duplicate elements from WebDriverAgent (e.g. the Face ID alert) are listed once, so their selectors are no longer ambiguous
- Native lane (iOS): `native_notifications` explains how to open a notification in the Notification Center — the first tap expands a group of one app's notifications, and a tap that only slides a notification aside is followed by a tap on "Open"
- CLI: native lane commands `native-*` mirroring every MCP `native_*` tool (except `native_connect` / `native_disconnect`, replaced by `native-connect`, `native-disconnect` and `native-sessions`). The device-side server runs detached from the CLI between commands and the WebDriver session is reused; `--native-session <name>` drives several devices at once
- Native lane (iOS): a WebDriverAgent already running for the simulator is reused instead of failing with a port conflict — WebDriverAgent 16 does not report the simulator UDID, so the check never matched; port 8100 taken by another program now fails at once with a hint instead of after 60 s
- Native lane (Android): disconnecting from a UIAutomator2 server another process started no longer stops it — UIAutomator2 stops itself when its session is deleted
- Native lane (Android): `foregroundApp` reports `com.android.systemui` while the notification shade is open, instead of the app below it
- Native lane: `native_enter_text` finds the field again and retries once when it changed before anything was typed (a screen still moving, a refused set-text), and its `label` also matches the first line of a field's label — a focused Flutter field on iOS adds its hint as a second line
- Native lane: add `native_notifications` — open / close the notification shade (Android) or Notification Center (iOS)
- Native lane: selectors ignore off-screen (zero-size) elements and `native_get_elements` no longer lists them; a target that exists only off screen fails with a hint to scroll
- Native lane: when no element matches and a scrollable container is on screen, the error also suggests `native_scroll` — a lazy list does not build far items, so they are not in the tree; ambiguity errors escape line breaks in ids, as in texts
- Native lane: `native_wait_for` retries a failed tree read (e.g. while the app is starting) instead of ending the wait; the server log of a failed tool now includes its error
- Native lane: `native_wait_for`, the server instructions and `help-ai` advise waiting for an element of the expected screen rather than an app's package name
- Native lane (Android): a device locked after a restart (PIN / pattern / password) fails `native_connect` at once with `deviceLocked` and a hint to unlock it, instead of a 30 s health-check timeout
- Native lane: a local port held by a dual-stack listener (IPv6 `*`, e.g. `python3 -m http.server`) is no longer taken for free — an iOS connect fails at once with `portConflict`
- CLI: a `native-*` command without a required option is a usage error (exit code 64) instead of a crash; `native-connect` errors use CLI command names
- Native lane (Android): `native_notifications` open / close wait until the shade has moved, so the next read reports `foregroundApp` correctly
- Native lane: `native_tap` and `native_enter_text` refuse a disabled element instead of touching its position — on iOS the app's elements stay listed, disabled, under a system sheet or picker, and the touch landed on the picker
- Native lane (Android): the content of password fields (e.g. a WebView `<input type="password">`) is masked in `native_get_elements`, one bullet per character, as WebDriverAgent does on iOS
- Native lane (iOS): elements outside the frame of their WebView or scroll view (e.g. a WebView page below the bottom tabs) are no longer listed or matched; partly visible ones are clipped to the frame
- Native lane (iOS): the hint for `native_press_key key=back` suggests an edge swipe long enough for iOS to go back (`native_swipe` to about 70 % of the screen width); `native_scroll` with `startX` / `startY` reports that start point instead of "screen center"
- Native lane (iOS): `native_hide_keyboard` no longer fails when the keyboard is already hidden — a dismissed keyboard stays in the WebDriverAgent tree below the screen and was reported as shown
- Native lane (Android): pick a free local port for UIAutomator2 (or `MARIONETTE_UIA2_PORT`), reuse a healthy server already forwarded for the device, install APKs only when they changed, and verify downloaded APKs against pinned SHA-256 checksums

# 0.7.0

- **Behaviour change:** `get_interactive_elements` now reports only primitive-valued properties (`bool`, `num`, `String`, `Enum`) for every caller. The `ButtonStyle`, `TextStyle`, `InputDecoration` and colour blobs that previously dominated the payload are gone from every level of output, which shrank by about a quarter on the example app. A `TextField`'s `decoration.labelText`/`hintText` is now surfaced as `label` so keyless fields keep a human-readable handle
- **Behaviour change:** `get_interactive_elements` now compacts its payload by default (`MarionetteConfiguration.compaction` defaults to `CompactionMode.compact`). On top of the primitive filter it drops rendering details and text font metrics, drops a `Text` element's duplicated `data`, rounds `bounds` to whole logical pixels, and reports `visible` only when an element is not visible — about 65% smaller than before on the example app. Nothing it drops is read by `tap`, `enter_text`, `scroll_to` or `swipe`, which match on key, identifier, text, type or coordinates. Set `compaction: CompactionMode.none` to get the full property dump back
- Add a `compaction` parameter to `get_interactive_elements` (`--compaction=<none|compact>` in the CLI) that overrides `MarionetteConfiguration.compaction` in both directions, so an agent can ask for the full payload on an app that keeps the default. `CompactionMode` deliberately has only `none` and `compact`: a third level is planned, but shipping a value that behaves exactly like `compact` would mislead, and enum values can be added later
- Add `isInteractiveElement` and `shouldStopTraversalAtElement` configuration callbacks that receive an `Element`, and deprecate the `Type`-based `isInteractiveWidget` and `shouldStopTraversal` ([#125](https://github.com/leancodepl/marionette_mcp/issues/125))
- Fix `get_interactive_elements` not recognizing generic built-in widgets (`DropdownButton<T>`, `DropdownButtonFormField<T>`, `Radio<T>`, `RadioListTile<T>`, `PopupMenuButton<T>`) and subclasses of built-in widgets, such as `ElevatedButton.icon`
- Fix `press_back_button` on a page-based `Navigator` (as produced by `go_router`) that refuses the pop while a route is still animating in — it now waits for the route transition to finish before popping (other animations, such as a loading spinner, don't hold it up) instead of tripping `navigator.dart`'s internal route-lifecycle assertion, which used to fail every navigation for the rest of the session ([#113](https://github.com/leancodepl/marionette_mcp/issues/113))
- Fix `register`/`unregister` rejecting instance names with dots or colons, such as device IDs like `192.168.1.1:5555` — only `/`, `\`, and control characters are disallowed now, and names are encoded into portable, Windows-safe file names on disk
- Add `marionette-flutter-drive-app`, an Agent Skill shipped inside the `marionette_flutter` package, installable via `dart run skills@ get` (Dart's [package skills](https://dart.dev/tools/pub/package-skills) convention) or `npx skills add leancodepl/marionette_mcp` — see the new "Agent Skill" section in the README
- Add opt-in session reports: with `MarionetteConfiguration(enableSessionReports: true)`, `connect`/CLI commands log to a per-run `.marionette/sessions/` directory (`steps.md`, screenshots, and an agent-written `report.md`) — see [Session Reports](./docs/session-reports.md)
- Add `set_device_config` tool and `set-device-config` CLI command for overriding text scale, bold text, and platform brightness in a running app — opt in by wrapping your root widget in the new `MarionetteDeviceConfig`
- Add `ancestor_keys` to `tap`, `secondary_tap`, `double_tap`, `long_press`, `swipe`, `pinch_zoom`, `scroll_to` and `enter_text`, and a repeatable `--ancestor-keys` to the matching CLI commands, to scope a match to one subtree when the same key repeats across identical subtrees (grid cells, repeated cards, embedded app instances) — keys nest outermost first, only descendants of the last one match, and a key with no element fails the call by name instead of widening the search; `scroll_to` keeps scrolling first, so a scope inside a lazily built list works
- Add `ancestor_keys` to `get_interactive_elements`, and `--ancestor-keys` to `get-interactive-elements`, to list only one subtree — the same chain can then be passed to the matcher tools to act inside it
- Add matching by Semantics `identifier` to the matcher tools (`--identifier` in the CLI), and report each element's `identifier` in `get_interactive_elements` ([#90](https://github.com/leancodepl/marionette_mcp/pull/90))
- Fix extension errors being reported as the generic `Server error` instead of the detail the extension returned — this silently swallowed every validation message and setup instruction, including the `get_logs` log-collector onboarding help
- Fix `press_key` with `enter` not submitting the focused text field: it now performs the field's text input action, so `onSubmitted` runs, while a multiline field still gets a new line ([#117](https://github.com/leancodepl/marionette_mcp/pull/117))
- Fix `MarionetteBinding.ensureInitialized()` silently hanging the app when another binding, such as the one `SentryFlutter.init` installs, was created first — it now throws an error that says to initialize `MarionetteBinding` first ([#96](https://github.com/leancodepl/marionette_mcp/issues/96))
- Fix `connect` hanging forever when the app's Dart Development Service stops answering stream subscriptions: it now waits at most 500 ms for the Service stream and continues, and `hot_reload`/`hot_restart` report failure in that state ([#127](https://github.com/leancodepl/marionette_mcp/pull/127))
- Fix `scroll_to` on layered UIs: scroll the list the user can reach and stop at the reachable copy of the target, instead of dragging a screen covered by a bottom sheet, dialog, or pushed route
- Fix `scroll_to` missing a target that only comes into view on its final drag, at either end of a list
- Fix `scroll_to` being unable to reach targets in long lists: it now scrolls by a share of the visible viewport instead of a fixed 64px, so lists past roughly 170 rows are reachable and shorter ones take far fewer gestures
- Fix `scroll_to` on screens with more than one scrollable: when the target is not built yet it now tries the two best-ranked reachable scrollables in turn rather than committing to a single guess, so a chip row, tab strip or nav rail no longer swallows the gesture
- Fix `scroll_to` reporting an attempt count instead of the cause when no scrollable could move at all: it now fails with `no Scrollable could be scrolled to reveal it`
- Fix every pointer gesture (`tap`, `double_tap`, `long_press`, `secondary_tap`, `swipe`, `pinch_zoom`, `scroll_to`) silently doing nothing, and every element being reported `visible: false`, in an app whose content is not in the implicit view — as with the desktop windowing API: gestures are now dispatched to, and visibility measured against, the view the element is actually in

# 0.6.0

- Promote schema-bearing custom extensions to first-class MCP tools via the new `ExtensionInputSchema`/`ExtensionParam` DSL
- Add `press_key` tool for dispatching hardware key events with modifiers
- Add `hot_restart` tool for fully restarting the app from `main()`
- Add `secondary_tap` tool for right mouse button clicks on desktop
- Add `swipe` CLI command for element- and coordinate-based swipe/drag gestures
- Surface `Semantics(label:)` and `Semantics(value:)` in `get_interactive_elements`
- Exit the stdio MCP server on stdin EOF to prevent orphaned processes
- Bump `mcp_dart` to `^2.1.0` and drop the bespoke Copilot-compat stdio transport
- Add a `Dockerfile` for building `marionette_mcp` as a container image

# 0.5.0

- **Breaking:** Pass `Element` instead of `Widget` to the `extractText` configuration callback, giving access to the full element context. Migration: change `(widget)` to `(element)` and use `element.widget` to access the widget.
- Add gesture support across all layers: `swipe/drag`, `long_press`, `double_tap`, `pinch_zoom`, and `press_back_button`.
- Add video recording with TCP/WS transport and Android auto-fallback.
- Improve screencast stability with broken-pipe race handling, concurrent stop safety, and orphaned session cleanup.
- Improve runtime robustness around input validation, resource cleanup, and non-monotonic timestamp handling.
- Strengthen release CI with explicit minimum-version compatibility checks and Flutter version sourced from `.fvmrc`.

# 0.4.0

- Add `marionette_cli` package with multi-instance CLI support
- Add `call_custom_extension` tool for arbitrary VM service extensions
- Add custom extension registry with `registerMarionetteExtension`
- Add focused selector to `enter_text`
- Add version compatibility check on connect
- Decouple logging from `marionette_flutter` into `marionette_logger` and `marionette_logging`
- Improve `ScrollSimulator` with reverse scrolling direction and configurable max scroll attempts
- Fix tap matching widgets behind modal route barriers
- Fix `onChanged` not being called on `enter_text`
- Fix pointer device collision with macOS mouse cursor
- Fix extracted text not being exposed in interactive elements
- Ensure correct status code range in `MarionetteExtensionError`

# 0.3.0

- Add screenshot resizing configuration
- Fix SIGTERM handling on Windows
- Add GitHub Copilot support
- Require Dart 3.10 for the MCP server
- Fix `hot_reload` tool response handling

# 0.2.4

- Add CI workflow with analyze, format, and version checks
- Add version generation script with validation and robustness
- Replace example symlinks with actual directories in both packages
- Improve project structure and dependencies

# 0.2.3

- Add example symlinks for improved pub.dev package scoring
- Fix documentation lints for angle brackets in code references

# 0.2.2

- Add compatibility for Copilot `initialize` call
- Make configuration parameter optional in `MarionetteBinding.ensureInitialized()`

# 0.2.1

- Update README

# 0.2.0

- Support tapping by widget type
- Support tapping by coordinates
- Return more info in `get_interactive_elements`
- Add hot reload tool, and return logs only since last hot reload
- `get_interactive_elements` returns only hittable elements now
- The tools have better naming to conform to the MCP implementations
- `scroll_to` does not assume that the widget is in the tree
- `Text` is a stopwidget now

# 0.1.0

- Initial version of Marionette MCP
- Support for getting the interactive widget tree
- Support for entering text
- Support for tapping and scrolling
- Support for getting logs from `logging` package
