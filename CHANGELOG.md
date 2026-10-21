# Unreleased

- `get_interactive_elements` (and `marionette get-interactive-elements`) warns when the app is not in front — a dialog, the notification shade, a biometric prompt, a browser or another screen covers it; `marionette_flutter` reports the app lifecycle state with the elements ([D22](docs/native-lane-decisions.md#d22))
- Native lane: errors from `native_connect` and the `native_*` tools now name the failing stage (iOS bootstrap included) and end with a `Hint:` describing how to fix it
- Native lane: fix `foregroundApp` in `native_get_elements` always being `null` on Android 10+
- Native lane: decode numeric character references (e.g. `&#10;`) in native element text, so multi-line labels can be matched by `native_tap` / `native_enter_text`
- **Breaking (native lane):** element-targeting tools (`native_tap`, `native_enter_text`, `native_scroll`) share one selector — `text` (`label` in `native_enter_text`), `textContains`, `id`, `type`, `index`. When a selector matches several elements and clickable ones do not narrow it to one, the tool fails and lists the candidates instead of acting on the first match; pass `index` or a more specific selector ([D1](docs/native-lane-decisions.md#d1))
- **Breaking (native lane, iOS):** all native coordinates — `bounds` and `x`/`y`/`startX`/`startY`/`distance` — are screenshot pixels on every platform; on iOS they were WebDriverAgent points ([D2](docs/native-lane-decisions.md#d2))
- Native lane: tap and type into exactly the element the selector chose (iOS no longer re-locates it by accessibility id, which could hit another element with the same id)
- Native lane: `native_scroll` uses the real screen size instead of inferring it from element bounds
- Native lane (Android): an empty text field is identified by its hint (placeholder) text; (iOS) software keyboard keys are reported as clickable
- Native lane: add `native_press_key` (back, home, enter, backspace, tab, recents, volume_up, volume_down) and `native_hide_keyboard`; `native_enter_text` types into the focused field when no selector is given and accepts `clear` ([D14](docs/native-lane-decisions.md#d14))
- Native lane: re-establish a lost device-side session automatically once; reads are retried, actions check that the server responds first and are only repeated when they certainly did not run ([D3](docs/native-lane-decisions.md#d3))
- Native lane (iOS): `native_connect` with the `udid` of a simulator that is not booted now fails immediately with a hint, instead of `xcodebuild` silently booting it headless
- Native lane: `native_get_elements` reports element state — `value` (text field content), `enabled`, `focused` (Android), `checked`, `selected`, `scrollable` — only when it carries information, and accepts filters (`text`, `textContains`, `id`, `type`, `clickableOnly`, `includeForegroundApp`). On iOS the typed content of a Flutter field is now visible ([D15](docs/native-lane-decisions.md#d15))
- **Breaking (native lane, Android):** a filled text field keeps its label (hint) as `text`; its content moved to `value`, matching iOS. Selectors by label keep finding the field after typing ([D15](docs/native-lane-decisions.md#d15))
- Native lane: add `native_wait_for` (visible / gone with timeout), `native_long_press`, `native_double_tap`, `native_pinch` and `native_swipe` (start and end coordinates)
- Native lane: `native_scroll` can swipe inside a container (`within`), takes `maxSwipes`, stops at the end of the content, ignores off-screen (zero-size) matches, and searches with slow drags that do not fling past the target ([D16](docs/native-lane-decisions.md#d16))
- Native lane: add `native_map_flutter_rect`, converting Flutter lane bounds to native screenshot pixels for gestures on platform views; `marionette_flutter` adds the `marionette.getViewMetrics` extension it reads ([D13](docs/native-lane-decisions.md#d13))
- Native lane (Android): reads of the UI tree no longer take 10 s on screens with continuous animation (video, maps) — UIAutomator2's idle wait is lowered to 500 ms ([D18](docs/native-lane-decisions.md#d18))
- Native lane (iOS): elements scrolled out of view (e.g. a WebView's whole page) are no longer listed or matched, and partly visible ones are clipped to the screen so their center can be tapped ([D16](docs/native-lane-decisions.md#d16))
- Native lane: `native_scroll` no longer reports the end of the content while crossing a large uniform area (it needs two swipes without a visible change); `native_wait_for` never runs past `timeoutMs` when a tree read is slow ([D16](docs/native-lane-decisions.md#d16))
- Native lane: a lost-session error arriving after `native_disconnect` / shutdown no longer starts a new session ([D3](docs/native-lane-decisions.md#d3))
- Fix: the stdio server exits on stdin EOF while connected to an app (the VM service connection kept the process alive)
- Native lane: add `native_biometrics` — `match` / `nonMatch` answer a biometric prompt on an emulator / simulator, `enroll` / `unenroll` on the iOS Simulator ([D20](docs/native-lane-decisions.md#d20))
- Native lane (Android): tree reads no longer fail while a toast is shown — they wait until it disappears (up to 5 s), then fail with a hint to use `native_take_screenshot`; where UIAutomator2 reports the toast (e.g. API 28) it is listed read-only by `native_get_elements` and `native_wait_for` ([D19](docs/native-lane-decisions.md#d19))
- Native lane (Android): `native_hide_keyboard` no longer presses Back when only Gboard's floating toolbar is shown (hardware keyboard attached) — Back closed the current screen; it fails with a hint instead ([D14](docs/native-lane-decisions.md#d14))
- Native lane (iOS): identical duplicate elements from WebDriverAgent (e.g. the Face ID alert) are listed once, so their selectors are no longer ambiguous ([D1](docs/native-lane-decisions.md#d1))
- Native lane (iOS): `native_notifications` explains that a notification in the Notification Center opens with a swipe right, not a tap, and when a simulated push shows a banner ([D21](docs/native-lane-decisions.md#d21))
- Native lane (Android): `native_app` says that `terminate` / `restart` also remove the app's notifications ([D11](docs/native-lane-decisions.md#d11))
- CLI: native lane commands `native-*` mirroring every MCP `native_*` tool (except `native_connect` / `native_disconnect`, replaced by `native-connect`, `native-disconnect` and `native-sessions`). The device-side server runs detached from the CLI between commands and the WebDriver session is reused; `--native-session <name>` drives several devices at once ([D4](docs/native-lane-decisions.md#d4))
- CLI: `marionette doctor` checks the native lane — adb and devices, the UIAutomator2 APKs (cache checksum or `MARIONETTE_UIA2_*_APK`), booted iOS Simulators, the WebDriverAgent build (`MARIONETTE_WDA_*` or cache), port 8100 taken by another program, orphaned device servers and native sessions whose server is gone
- Native lane (iOS): a WebDriverAgent already running for the simulator is reused instead of failing with a port conflict — WebDriverAgent 16 does not report the simulator UDID, so the check never matched; port 8100 taken by another program now fails at once with a hint instead of after 60 s ([D10](docs/native-lane-decisions.md#d10))
- Native lane (Android): disconnecting from a UIAutomator2 server another process started no longer stops it — UIAutomator2 stops itself when its session is deleted ([D10](docs/native-lane-decisions.md#d10))
- Native lane (Android): `foregroundApp` reports `com.android.systemui` while the notification shade is open, instead of the app below it
- Native lane (Android): `native_open_url` and `native_app restart` say to wait for the app's first screen before a deep link — one sent during a cold start is lost ([D11](docs/native-lane-decisions.md#d11))
- Native lane: `native_enter_text` finds the field again and retries once when it changed before anything was typed (a screen still moving, a refused set-text), and its `label` also matches the first line of a field's label — a focused Flutter field on iOS adds its hint as a second line ([D14](docs/native-lane-decisions.md#d14), [D15](docs/native-lane-decisions.md#d15))
- Native lane: a session lost while the server still answers (another client took UIAutomator2's single session) is recovered by opening a new session on the same server instead of restarting it ([D3](docs/native-lane-decisions.md#d3))
- Native lane: device shortcuts — `native_permissions` (grant / revoke / reset without the system dialog; reports when the change terminated the app), `native_open_url` (web pages and deep links), `native_app` (activate / background / terminate / restart), `native_notifications` (open / close the shade or Notification Center, iOS push), `native_device_info`, `native_set_orientation`, `native_set_location` ([D7](docs/native-lane-decisions.md#d7), [D9](docs/native-lane-decisions.md#d9), [D11](docs/native-lane-decisions.md#d11), [D12](docs/native-lane-decisions.md#d12), [D17](docs/native-lane-decisions.md#d17))
- Native lane: selectors ignore off-screen (zero-size) elements and `native_get_elements` no longer lists them; a target that exists only off screen fails with a hint to scroll ([D16](docs/native-lane-decisions.md#d16))
- Native lane: when no element matches and a scrollable container is on screen, the error also suggests `native_scroll` — a lazy list does not build far items, so they are not in the tree; ambiguity errors escape line breaks in ids, as in texts ([D16](docs/native-lane-decisions.md#d16))
- Native lane (Android): a device locked after a restart (PIN / pattern / password) fails `native_connect` at once with `deviceLocked` and a hint to unlock it, instead of a 30 s health-check timeout ([D10](docs/native-lane-decisions.md#d10))
- Native lane: a local port held by a dual-stack listener (IPv6 `*`, e.g. `python3 -m http.server`) is no longer taken for free — `marionette doctor` reports port 8100 and an iOS connect fails at once with `portConflict` ([D10](docs/native-lane-decisions.md#d10))
- CLI: a `native-*` command without a required option is a usage error (exit code 64) instead of a crash; `native-connect` errors use CLI command names ([D4](docs/native-lane-decisions.md#d4))
- Native lane (Android): `native_notifications` open / close wait until the shade has moved, so the next read reports `foregroundApp` correctly ([D12](docs/native-lane-decisions.md#d12))
- Native lane: `native_tap`, `native_enter_text` and the gestures refuse a disabled element instead of touching its position — on iOS the app's elements stay listed, disabled, under a system sheet or picker, and the touch landed on the picker ([D1](docs/native-lane-decisions.md#d1))
- Native lane (Android): the content of password fields (e.g. a WebView `<input type="password">`) is masked in `native_get_elements`, one bullet per character, as WebDriverAgent does on iOS ([D15](docs/native-lane-decisions.md#d15))
- Native lane (iOS): elements outside the frame of their WebView or scroll view (e.g. a WebView page below the bottom tabs) are no longer listed or matched; partly visible ones are clipped to the frame ([D16](docs/native-lane-decisions.md#d16))
- Native lane (iOS): the hint for `native_press_key key=back` suggests an edge swipe long enough for iOS to go back (`native_swipe` to about 70 % of the screen width); `native_scroll` with `startX` / `startY` reports that start point instead of "screen center" ([D14](docs/native-lane-decisions.md#d14))
- Native lane (iOS): `native_hide_keyboard` no longer fails when the keyboard is already hidden — a dismissed keyboard stays in the WebDriverAgent tree below the screen and was reported as shown ([D14](docs/native-lane-decisions.md#d14))
- Native lane: `native_take_screenshot` captures a single element when given a selector ([D6](docs/native-lane-decisions.md#d6))
- Native lane (Android): pick a free local port for UIAutomator2 (or `MARIONETTE_UIA2_PORT`), reuse a healthy server already forwarded for the device, install APKs only when they changed, and verify downloaded APKs against pinned SHA-256 checksums ([D10](docs/native-lane-decisions.md#d10))

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
