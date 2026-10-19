# Native lane — design decisions

Records of the design decisions behind the native automation lane (`native_*` tools). Each record explains the dilemma, the options that were considered, what was chosen and why, the consequences, and how the decision was verified. Records are never deleted: when a decision changes, its status says so and the record explains what was learned.

Decisions are referenced from the code (`See docs/native-lane-decisions.md#dN`) and from the changelog.

| # | Topic | Status |
| --- | --- | --- |
| [D1](#d1) | Ambiguous element selectors | Accepted |
| [D2](#d2) | Coordinate space of the native lane | Accepted |
| [D3](#d3) | Automatic recovery of a lost session | Accepted |
| [D10](#d10) | UIAutomator2 local port and server reuse | Accepted |
| [D14](#d14) | Software keyboard and key presses | Accepted |

---

<a id="d1"></a>

## D1 — Ambiguous element selectors

- **Status:** Accepted (2026-10-16)
- **Applies to:** `NativeSelector`, `selectElement`, `native_tap`, `native_enter_text`, `native_scroll`; element lookup in `AndroidNativeConnector` / `IosNativeConnector`.

### Context and dilemma

System screens often contain several elements with the same or similar label: two "Request" buttons on one screen, a button and its own text label with identical text (common on iOS, where a `Button` contains a `StaticText`), "Allow" next to "Allow only while using the app". The tools used to act on the *first* element in tree order with an exact `text` or `id`, so the agent could tap the wrong control and still get a success message. Making matching stricter, on the other hand, can break calls that work today.

### Options considered

1. **Keep "first match".** No behaviour change; silent mistakes with repeated labels that are hard for the agent to notice.
2. **Always fail on more than one match.** Safest, but breaks the common case of a label inside a button, which then matches twice.
3. **Prefer clickable elements, then fail with the candidates.** Resolves the label-inside-button case and reports real ambiguity together with how to resolve it.

### Decision

Option 3. One selector is shared by every tool that targets an element: `text` (exact; `label` in `native_enter_text`, whose `text` is the string to type), `textContains` (case-insensitive), `id`, `type` (full class or short name such as `Button`) and `index`. All given fields must match.

- With `index`, the n-th of **all** matches (0-based, UI-tree order, the order of `native_get_elements`) is used — before the clickable preference, so it is stable and predictable.
- Without `index`: one match is used; with several, clickable ones are preferred; if more than one remains (or several non-clickable ones match), `NativeAmbiguousElementException` lists every candidate (`[i] type text id clickable bounds`) with the hint to pass `index` or a more specific selector.
- No match: `NativeElementNotFoundException`, listing up to five near misses (same text ignoring case and whitespace, or containing it) — e.g. `"Amount\nDigits only"` when asked for `"Amount"`.
- **The chosen element is the one acted on.** Connectors must not re-locate it by id or label, which could return another element with the same id: iOS `tapElement` taps the element's center; iOS `enterText` locates the WDA element by type and exact geometry from the same tree; Android `enterText` uses the field that received focus from the tap before trying `resource-id`.

### Rationale

For an agent, an error listing the candidates is cheaper than tapping the wrong control, noticing, undoing and retrying. The clickable preference removes the most frequent false conflict, so most existing calls keep working.

### Consequences

- **Behaviour change:** calls that used to act on "the first match" now fail when the match is genuinely ambiguous (changelog entry). Tool descriptions and the server instructions explain the rule.
- New selector fields are available in all element-targeting tools.
- iOS taps no longer go through WebDriverAgent's element click; they are coordinate taps at the element's center (verified to work on app UI and on SpringBoard alerts).

### Verification

- Unit tests cover the full matrix (`native_selector_test.dart`) and the tools (`native_tools_test.dart`); fixture tests (`fixtures_test.dart`) run the selector on UI trees captured from Android 9 and iOS 26.4.
- Live, Android API 28 and 35, iOS 26.4 and 18.6: `native_tap text="Request"` on the example app's permission screen fails with two candidates; `index: 0` / `index: 1` open the camera / photos dialog respectively; "Tap me (native)" (button + label) resolves to the button.
- Verification found that iOS `tapElement` re-located the element by its accessibility id, so `index: 1` tapped the *first* "Request" button (same id). This led to the "chosen element is the one acted on" rule above.

---

<a id="d2"></a>

## D2 — Coordinate space of the native lane

- **Status:** Accepted (2026-10-16)
- **Applies to:** `NativeBounds`, `NativeScreen`, `NativeConnector.getScreen`, `WebDriverNativeConnector.serverUnitScale`, every `x` / `y` / `startX` / `startY` / `distance` argument and every `bounds` value.

### Context and dilemma

UIAutomator2 reports and accepts physical pixels, which match the pixels of its screenshots. WebDriverAgent reports and accepts **points**, while its screenshots are in pixels (×2 or ×3). The documentation claimed "physical pixels" everywhere. An agent reading a position off a screenshot and passing it to `native_tap` would miss by the scale factor on iOS. In addition, `native_scroll` inferred the screen size from the largest element bounds, falling back to 1080×1920.

### Options considered

1. **Native units per platform** (pixels on Android, points on iOS). Simplest, but the agent must know the platform and scale, and screenshots do not match `bounds` on iOS.
2. **Logical points everywhere.** Matches the Flutter lane, but needs scaling on Android and matches screenshots on neither platform.
3. **Screenshot pixels everywhere.** What the agent sees in the image is exactly what it passes to the tools; the conversion is hidden in the connector.

### Decision

Option 3. All native-lane coordinates — input and output — are pixels of the image returned by `native_take_screenshot`.

- `WebDriverNativeConnector` converts with `serverUnitScale`: element bounds from the server are multiplied by it; coordinates sent to the server are divided by it (rounded). Android: 1. iOS: the display scale.
- iOS reads the scale once per session from `GET /session/{id}/wda/screen`; if that endpoint is missing it derives it from the screenshot width divided by the window width in points; if both fail, `native_connect` fails rather than guessing.
- `NativeConnector.getScreen()` returns the screen size in screenshot pixels and the scale. Android uses UIAutomator2's `GET /session/{id}/window/current/size` (UIAutomator2 does not implement the W3C `window/rect`), falling back to `adb shell wm size`. `native_scroll` uses it instead of inferring the size from element bounds.
- The Flutter lane stays in logical pixels; mixing the two remains forbidden.

### Rationale

Agents work with screenshots. One coordinate space that matches the image removes a whole class of mistakes and does not require the agent to know the platform.

### Consequences

- **Behaviour change on iOS:** `bounds` values are multiplied by the display scale, and `x` / `y` arguments are interpreted as pixels (changelog entry).
- Coordinates sent to WebDriverAgent are rounded to whole points (no practical effect).
- Tool descriptions say "screenshot pixels" instead of "physical pixels".

### Verification

- WDA (iOS 26.4, iPhone 17): `window/size` and `window/rect` return 402×874 (points), `wda/screen` returns scale 3, screenshots are 1206×2622 — confirming that WDA works in points. UIAutomator2 (API 28): `window/current/size` 1080×2160 equals the screenshot and `wm size`; `window/rect` is an unknown command. API 35: `getScreen()` 1280×2856 equals the screenshot, and a tap at a button's screenshot-pixel center hit it.
- Unit tests cover the conversion (bounds ×3, taps and swipes ÷3, `getScreen`, the screenshot-based fallback, failing connect) and `native_scroll` geometry from the real screen size; fixture tests check that the converted iOS application element spans exactly the screenshot.
- Live, iOS 26.4 and 18.6 (iPhone 17: 402×874 pt, iPhone 16 Pro Max: 440×956 pt, both scale 3): a tap at the native button's center taken from its screenshot-pixel bounds — (603, 1365) and (660, 1632) — hit the button; the application element converts to exactly the screenshot size (1206×2622, 1320×2868); candidates in ambiguity errors show pixel bounds (e.g. `(819, 1278, 315x144)`).

---

<a id="d3"></a>

## D3 — Automatic recovery of a lost session

- **Status:** Accepted (2026-10-15)
- **Applies to:** `RecoveringNativeConnector`, `NativeServiceContext.connect`, `WebDriverClient` error markers, every session-bound `native_*` tool.

### Context and dilemma

The device-side servers (UIAutomator2 on Android, WebDriverAgent on iOS) disappear for reasons outside the agent's control: the app under test is reinstalled, the emulator or simulator restarts, the server process is killed. Without handling, every later call failed with a raw socket error and the agent had to work out that it needs `native_connect` again.

Re-establishing the session and repeating the failed call is convenient, but repeating an *action* is dangerous: if the server executed a tap and then died before answering, repeating it taps twice (a second purchase, a second dismissed dialog).

### Options considered

1. **No recovery, only a clear error.** Safe, but every server hiccup costs the agent an extra round trip and a reconnect it has to remember to do.
2. **Recover and repeat every operation.** Convenient, but can perform an action twice.
3. **Recover once; repeat reads always and actions only when they certainly did not run.** Convenient in the common case without the double-action risk.

### Decision

Option 3. `NativeServiceContext.connect` wraps the platform connector in a `RecoveringNativeConnector`, which classifies every operation by its `NativeConnector` method:

- **Reads** — `getNativeElements`, `foregroundApp`, `takeScreenshot`. On a lost session the session is re-established once (same `platform` / `serial` / `udid` as the `native_connect` call) and the read is repeated.
- **Actions** — `tapElement`, `tapAt`, `enterText`, `swipe`. Before an action is sent, the server is probed (`isServerResponding`, `GET /status`, 5 s timeout); a server that is already gone is replaced first, so the action is then sent to a healthy session. An action is repeated after re-establishing the session **only** when it certainly did not run:
  - the server answered `invalid session id` (it rejected the request), or
  - no connection could be opened, so the request was never sent (`server unreachable`).
- If the connection broke **after** the request was sent (`connection lost`), the action may have run. It is not repeated; the tool fails with `NativeSessionLostException` ("the action may or may not have been performed", hint: check with `native_get_elements`) and the session is re-established at the start of the next call.
- If the session is lost again right after re-establishing it, or re-establishing fails, the context disconnects and the error asks for `native_connect`.
- The pre-action probe exists because of Android: traffic goes through `adb forward`, which accepts the local connection even when the device-side server is dead, so without the probe a dead server is only noticed after the action was sent — i.e. as `connection lost`, with an unknown outcome. The probe costs one local request per action; the outcome stays unknown only if the server dies between the probe and the action.
- Concurrent calls that hit the same loss (e.g. the tree and the foreground app fetched in parallel by `native_get_elements`) share one re-establish.

**Where the logic lives.** Two shapes were tried:

1. Explicit `context.read(...)` / `context.act(...)` around every connector call in the tool handlers. It makes the retry semantics visible at each call site, but every tool (and every future tool) has to pick the right wrapper, and the naming read like a state-management API.
2. A `NativeConnector` decorator (chosen). Tool handlers keep calling `context.requireConnector()` like before; the classification lives in one class, and adding a method to `NativeConnector` forces a classification there because the decorator must implement it.

`WebDriverClient` tells the cases apart by where the I/O error happens: `dart:io` opens the connection inside `HttpClient.openUrl`, so a failure there means nothing was sent (`webDriverServerUnreachable`); a failure while sending or reading the response is `webDriverConnectionLost`.

### Rationale

Most losses happen between calls (the server died while the agent was thinking), so a transparent reconnect fixes them without the agent noticing. Classifying by "was the request sent" keeps actions exactly-once from the agent's point of view.

### Consequences

- `native_connect` remembers its arguments; `native_disconnect` forgets them.
- A recovery costs a full bootstrap: about 1.5 s on Android and 3–4 s on iOS (WebDriverAgent restart).
- Errors returned to the agent distinguish "action may have happened" from "action did not happen". The `native_connect` tool description explains the behaviour.

### Verification

- Unit tests (`native_service_context_test.dart`, `webdriver_client_test.dart`) cover every branch: read retried, action retried after `invalid session id` and after an unreachable server, action not repeated after a dropped connection, second loss, failed reconnect, unrelated WebDriver errors untouched.
- iOS Simulator 26.4: WebDriverAgent terminated with `simctl terminate` during a session — the next read (≈ 3.4 s) and the next tap (≈ 3.7 s) both succeeded after an automatic restart of WebDriverAgent; no `xcodebuild` process was left after `native_disconnect`.
- Android emulator (API 35): UIAutomator2 force-stopped during a session — the next read succeeded after an automatic restart (≈ 1.8 s). Without the pre-action probe, the next *action* failed with "may or may not have been performed", because behind `adb forward` a dead server surfaces as `connection lost` (after sending), never as `server unreachable`. This led to adding the probe; with it, a tap after UIAutomator2 was force-stopped succeeded after an automatic restart (≈ 3.1 s), and a tap on a healthy server took ≈ 0.16 s, as before. Same on API 28: read after force-stop ≈ 1.8 s, tap after force-stop ≈ 1.8 s with exactly one re-establish in the log; the first page source from a freshly restarted server took ≈ 1.4 s (server warm-up, not a reconnect), the next ≈ 70 ms.
- During verification the first implementation treated "connection refused" as "action may have happened"; since a refused connection means the request was never sent, the unreachable case was split out and made retryable (the version described above).

---

<a id="d10"></a>

## D10 — UIAutomator2 local port and server reuse

- **Status:** Accepted (2026-10-15)
- **Applies to:** `AndroidBootstrap`, `chooseUia2LocalPort`, `MARIONETTE_UIA2_PORT`.

### Context and dilemma

UIAutomator2 listens on port 6790 on the device and Marionette forwards a local port to it with `adb forward`. The local port used to be fixed at 8200, so two devices at once, or any other process on 8200, broke `native_connect`. Every `native_connect` also reinstalled both server APKs and restarted the server, even when an identical, healthy server was already running.

### Options considered

1. **Keep 8200.** Predictable, but breaks with several devices or a busy port.
2. **Derive the port from the device serial.** Deterministic, but opaque and can still collide.
3. **Configurable port, otherwise reuse an existing forward for the device, otherwise the first free port from 8200.**

### Decision

Option 3, in this order:

1. A port passed to the `AndroidBootstrap` constructor is used as-is (programmatic use and tests).
2. `MARIONETTE_UIA2_PORT`, when set, is used; if the port is busy, bootstrap fails with a `portForward` error and a hint. An invalid value is an error, not silently ignored.
3. Otherwise, if `adb forward --list` shows a forward from this device to port 6790, that port is used. If the server behind it is healthy, it is **reused**: no install, no restart, and it is **left running** on dispose because another Marionette process owns it.
4. Otherwise the first free local port in 8200–8299.

Independently, an APK is installed only when the copy on the device differs from the local file (SHA-256 of `pm path` + `sha256sum` on the device vs. the local file). Downloaded and cached release APKs are verified against pinned SHA-256 checksums; a corrupted cache file is downloaded again.

### Rationale

Zero configuration in the common single-device case (still port 8200), correct behaviour with several devices, and an escape hatch for fixed setups. Reusing a healthy server avoids a restart when one is already running for the device (e.g. left by another Marionette process, or for future CLI commands).

### Consequences

- The local port is no longer fixed; it is logged and available as `AndroidBootstrap.localPort`.
- A reused server is not stopped by `native_disconnect` of the process that reused it.
- **UIAutomator2 serves one session at a time.** A second process that connects to the same device reuses the server but its new session replaces the first process's session; the first process recovers on its next call (D3) and in turn replaces the second one. Two Marionette sessions driving the same device concurrently are therefore not supported — use one session per device.
- Old Android versions without `sha256sum` (or any failure to compute the checksum) fall back to installing, as before.
- `marionette_mcp` depends on `package:crypto` for SHA-256 (maintained by the Dart team, already in the dependency tree).

### Verification

- Unit tests (`android_bootstrap_test.dart`, `process_clients_test.dart`) cover port selection (explicit, environment, busy, invalid, first free, exhausted range), reuse of a healthy forward without install or teardown, restart on an unhealthy forward, install skipping, checksum mismatch and corrupted cache.
- Pinned checksums were computed from the v10.3.2 GitHub release assets and match the previously cached copies.
- Android emulator (API 35):
  - `sha256sum` is available on the device; the installed server APK hash equals the pinned one, and two consecutive `native_connect` calls left `lastUpdateTime` of both packages unchanged (no reinstall, connect ≈ 1.7 s).
  - `adb forward --list` prints `<serial> tcp:<local> tcp:<remote>` for all devices; the UIAutomator2 forward exists during a session and is removed on disconnect; an unrelated forward (Flutter's VM service) is ignored.
  - With a listener on 8200, the forward used 8201; `MARIONETTE_UIA2_PORT=8250` used 8250; `MARIONETTE_UIA2_PORT=8200` while busy and `MARIONETTE_UIA2_PORT=abc` failed immediately with a hint.
  - A second process connected in ≈ 0.1 s by reusing the running server and left it running on disconnect; the first process's next call took ≈ 1.9 s because its session had been replaced (see consequences).
- Android emulator (API 28): `sha256sum` is available and both installed APK hashes equal the pinned ones; two consecutive connects did not reinstall (`lastUpdateTime` unchanged, connect ≈ 1.7 s); the forward exists only during the session.

---

<a id="d14"></a>

## D14 — Software keyboard and key presses

- **Status:** Accepted (2026-10-16)
- **Applies to:** `native_press_key`, `native_hide_keyboard`, `native_enter_text` (focused-field mode, `clear`); `NativeConnector.pressKey` / `hideKeyboard` / `isKeyboardShown` / `typeText`.

### Context and dilemma

The software keyboard is a native window on both platforms. After typing it stays open and covers part of the app — in the example app, Flutter resizes above it and the bottom navigation bar disappears from the UI tree. On Android, Gboard does not publish its keys to accessibility, so an agent cannot type by tapping keys. Three choices had to be made: how to hide the keyboard without side effects, what typing does to existing text, and how to treat keys a platform does not have.

### Options considered

- **Hiding on Android:** (a) always press Back — hides the IME, but navigates back when no keyboard is shown; (b) Escape — not handled consistently by apps; (c) press Back **only while the IME is shown**, checked with `dumpsys input_method` (UIAutomator2 has no `is_keyboard_shown`).
- **Hiding on iOS:** (a) WDA `keyboard/dismiss` alone — fails for most keyboards ("Did not know how to dismiss the keyboard"); (b) tap `return` — dismisses single-line fields but inserts a newline in multi-line ones; (c) WDA dismiss restricted to non-editing keys (`Done`, `Hide keyboard`, `Dismiss`) and a clear failure otherwise; (d) tap outside the field — position-dependent, may hit a control.
- **Typing:** replace the field content, or append at the cursor like a user typing.
- **Unsupported keys:** silently ignore, or fail with a hint.

### Decision

- **Android:** `hideKeyboard` presses Back only if `mInputShown=true`, then waits (≤ 2 s) for the IME to close; when no keyboard is shown it returns false and sends nothing.
- **iOS:** `hideKeyboard` returns false without a keyboard; otherwise WDA dismiss with `Done` / `done` / `Hide keyboard` / `Dismiss` (never `return`). If WDA reports it cannot dismiss, the tool fails immediately with a hint (tap outside the field, use the app's Done button, or unfocus via the Flutter lane); after a reported success it waits briefly for the keyboard to disappear.
- **Typing appends** on both platforms; `clear: true` empties the field first (W3C element clear). Without a selector, `native_enter_text` types into the element that has keyboard focus (W3C `element/active`) — the way to type into Flutter fields on Android, where the keyboard is invisible to the native lane. The focused element must be a text field (Android `className` containing `EditText` / `AutoCompleteTextView`; iOS `type` text field, secure field, text view or search field); otherwise the tool fails and names what has focus. If the class cannot be read, typing proceeds unchecked.
- **Keys:** Android maps every key to a `KeyEvent` keycode (`press_keycode`). iOS: `home` (and `volume_*` on devices) through `wda/pressButton`; `enter` / `backspace` as `\n` / `\b` through `wda/keys`; `back`, `recents` and `tab` do not exist and fail with `NativeUnsupportedException` and a hint (the software keyboard has no Tab key — `\t` would be typed into the field as a character); a button the Simulator lacks (volume) is reported the same way. Key names match the Flutter lane's `press_key` where they overlap.

### Rationale

No operation may have a hidden side effect: an unconditional Back would navigate, `return` would edit text. A clear failure with a concrete next step is better than a guess. Appending matches what a user typing does and is identical on both platforms; replacing is one explicit flag away.

### Consequences

- Some iOS keyboards (number pad, default keyboard of a plain `UITextField`) cannot be hidden by the tool; the agent gets a hint instead.
- On iOS the typed text of a field labelled by Flutter (`label="Title"`) is reported as the label, not the value, in `native_get_elements` — to be addressed by the richer element model (N-01).

### Verification

- Endpoints probed live: UIAutomator2 `element/active`, W3C key actions and `press_keycode` type into a focused Flutter field (API 35); `is_keyboard_shown` is an unknown command. WDA `wda/keys` types into the focused field; `wda/keyboard/dismiss` without keys fails with "Did not know how to dismiss the keyboard"; `wda/pressButton` volume on the Simulator fails with "not supported".
- Live, Android API 28: the same results as on API 35 (fields found by their hint, typing appends, `clear`, backspace, hide restores the bottom tabs, a second hide does not navigate, back / home / volume / recents).
- Live, Android API 35: focused typing appends (`71` → `715`), `clear` replaces (`42`), backspace deletes, `native_hide_keyboard` hides the IME and the bottom tabs reappear, a second call reports "not shown" without navigating; back / home / volume work.
- Live, iOS 26.4 (iPhone 17 Pro Max): the same results as on 18.6, including a plain `UITextField` (`ab` + backspace → `a`) and `enter`. Follow-up checks: Polish characters ("zażółć gęślą jaźń", "Łódź ĄĘ €") are typed correctly into the focused field and through a selector, `clear` replaces the content in both modes, and typing with nothing focused fails with the "focus a field first" hint. `tab` was first mapped to `\t`; the screenshot showed a tab character typed into the Flutter field instead of a focus change, so `tab` became unsupported on iOS.
- Found through the MCP server on Android: after `tab` moved focus onto a list button, focused typing first returned a raw WebDriver error and then **reported success without typing anything** (UIAutomator2 accepts send keys on a button). This led to the focused-element class check above; afterwards the same call fails with "focus is on android.widget.Button" and typing into a real field still works.
- Live through the real MCP server (stdio JSON-RPC: `initialize`, `tools/list`, `tools/call`) on iOS 26.4 and Android API 35: tool schemas, focused typing, key presses including the unsupported-key and invalid-argument errors, `native_hide_keyboard` (hidden / not shown).
- Follow-up repeated through the MCP server on Android API 28 and iOS 18.6 with the same results: Polish characters in both modes (on iOS also in a Flutter field, checked on a screenshot), `clear` in both modes, `enter` (newline / submit) and `tab` (focus change) on Android, `tab` unsupported on iOS, the "focus a field first" error, and the focused-on-a-button rejection on Android.
- Live, Android API 35 (follow-up): Polish characters in both modes, `clear` through a selector, `enter` inserts a newline in a multi-line field and submits a single-line one (the keyboard closes), `tab` moves focus to the next field, typing with nothing focused fails with the hint.
- Live, iOS 18.6: focused typing appends and backspace deletes; the Flutter `Title` field (Done key) is hidden; the number pad and a plain `UITextField` fail fast (≈ 4 s, of which most is WDA trying keys) with the hint; home works; back / recents / volume are reported as unsupported.
- Unit tests cover keycode mapping, Back never sent without a keyboard, polling and failure, iOS key mapping, dismiss key names without `return`, fail-fast without polling, focused typing with clear, and decorator classification.

