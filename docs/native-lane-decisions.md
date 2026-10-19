# Native lane — design decisions

Records of the design decisions behind the native automation lane (`native_*` tools). Each record explains the dilemma, the options that were considered, what was chosen and why, the consequences, and how the decision was verified. Records are never deleted: when a decision changes, its status says so and the record explains what was learned.

Decisions are referenced from the code (`See docs/native-lane-decisions.md#dN`) and from the changelog.

| # | Topic | Status |
| --- | --- | --- |
| [D1](#d1) | Ambiguous element selectors | Accepted |
| [D2](#d2) | Coordinate space of the native lane | Accepted |
| [D3](#d3) | Automatic recovery of a lost session | Accepted |
| [D6](#d6) | Screenshot of part of the screen | Accepted |
| [D10](#d10) | UIAutomator2 local port and server reuse | Accepted |
| [D14](#d14) | Software keyboard and key presses | Accepted |
| [D15](#d15) | Element state and the label / content of text fields | Accepted |
| [D16](#d16) | Scrolling to an element and waiting for one | Accepted |

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

<a id="d6"></a>

## D6 — Screenshot of part of the screen

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_take_screenshot` (selector mode); `NativeConnector.takeElementScreenshot`, `WebDriverClient.elementScreenshot`.

### Context and dilemma

A full screenshot costs the agent many tokens, and often only one platform view, dialog or icon matters. Cropping an arbitrary rectangle inside Marionette needs PNG decoding and encoding — a new dependency (e.g. `image`) or a hand-written codec — while `marionette_mcp` avoids new dependencies.

### Options considered

1. The `image` package and cropping any rectangle.
2. A hand-written PNG decoder.
3. Only an element screenshot through the server's W3C endpoint (`GET /session/{id}/element/{eid}/screenshot`); rectangles postponed.

### Decision

Option 3. `native_take_screenshot` accepts the shared selector ([D1](#d1)); the selected element is located on the server and captured with the W3C element-screenshot endpoint. The element is located by its exact geometry from the same UI tree — UIAutomator2: class plus `@bounds="[x1,y1][x2,y2]"`; WebDriverAgent: type plus `@x/@y/@width/@height` in points — with the resource id as a fallback, so a repeated id or label cannot select another element. An arbitrary rectangle is not supported.

### Rationale

No new dependency, and the element case covers the main use (a platform view, a dialog). Locating by geometry reuses the approach that already fixed wrong-element taps on iOS ([D1](#d1)).

### Consequences

- No screenshot of an area without an element (e.g. part of a camera preview that has no accessibility node); to be reconsidered if the need appears.
- The element must still be on screen; if the tree changed between selection and capture the tool fails with "call native_get_elements and retry".

### Verification

- Endpoint probed live on both servers: UIAutomator2 (API 28) and WebDriverAgent (iOS 18.6) return a PNG of the element; on iOS in pixels, not points.
- Through the MCP server: Android API 28 — the pinch target (992×510 bounds) gives a 992×510 PNG; iOS 18.6 — the double-tap target (1224×288) gives 1224×288, the `horizontal_list` container 1224×190. The full screenshot is unchanged.
- Unit tests cover the geometry XPath on both platforms, the id fallback and the "element is gone" error.

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
- On iOS, `clear: true` (W3C element clear in WebDriverAgent) hides the keyboard while the field keeps focus; typing afterwards still works. Tapping a field that already has focus does not bring the keyboard back — tap another control (or unfocus) first.
- On iOS the typed text of a field labelled by Flutter (`label="Title"`) is reported as the label, not the value, in `native_get_elements` — to be addressed by the richer element model (N-01). *Resolved by [D15](#d15): the content is reported as `value`.*

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
- Follow-up (2026-10-19, iOS 18.6): `native_hide_keyboard` failed with "no Done / dismiss key" after a field was cleared. Cause: the iOS keyboard check only looked for `XCUIElementTypeKeyboard` in the page source, but a hidden keyboard stays in the tree, parked just below the screen (`y` = application height, `visible="false"`; screenshots confirmed no keyboard on screen). Hiding then tried to dismiss a keyboard that was not there. The keyboard now counts as shown only when it has a size and its top edge is above the bottom of the application; `visible` is not used because WDA reports it inconsistently. The Done key itself was enabled in the empty field, which ruled out the first guess (`enablesReturnKeyAutomatically`). Verified live: in that state the tool reports "Keyboard was not shown"; with a keyboard on screen (empty or filled field) it hides it. Unit tests cover the parked keyboard and an on-screen one.

---

<a id="d15"></a>

## D15 — Element state and the label / content of text fields

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_get_elements` (fields `value`, `enabled`, `focused`, `checked`, `selected`, `scrollable`; filters); `NativeElement`, `parseAndroidUiDump`, `parseWdaSource`; the `text` selector of every element-targeting tool.

### Context and dilemma

Agents could see what an element says, but not its state: whether a switch is on, a button disabled, a field focused, or what was typed into a field. iOS made the last one impossible: a Flutter field labelled "Title" reported only the label, and its content was nowhere ([D14](#d14)). Android did the opposite — once something was typed, `text` became the content and the label disappeared, so `native_enter_text label="Title"` stopped finding the field it had just typed into. Both servers expose state attributes, but with different names and with traps (see below). The output also must not grow much: every `native_get_elements` call is paid for in tokens.

### Options considered

- **Shape:** (a) the raw attribute maps of each platform; (b) one platform-neutral set of fields, each emitted only when it carries information.
- **Field text:** (a) `text` is whatever the platform reports (content on Android once typed, label on iOS); (b) `text` is the label or placeholder, the content goes to a separate `value` — on both platforms.
- **iOS `value`:** (a) report `value` for every element; (b) only for input types.

### Decision

- `NativeElement` gains `value`, `enabled`, `focused`, `checked`, `selected`, `scrollable`. JSON includes them only when non-default: `value` when present, `enabled: false`, `focused: true`, `checked` for checkable elements (both `true` and `false`), `selected: true`, `scrollable: true`.
- **Text fields keep their label in `text`** and report their content in `value`: Android takes `hint` → `content-desc` → `text` for `EditText` / `AutoCompleteTextView` (Flutter puts the label in `hint`, which stays after typing); `value` is `text` unless it is the hint (`showing-hint`, or equal to `hint`). iOS takes `label` → `placeholderValue` → `value` for text fields; `value` is reported unless it equals `placeholderValue` (an empty field reports its placeholder as its value).
- iOS `value` is reported only for text fields and sliders. Other types use it for unrelated state: a selected tab button reports `value="1"`, the keyboard's "Next keyboard" key reports the list of keyboards.
- `checked`: Android `checked` when `checkable="true"`; iOS `value` "1"/"0" of `Switch` / `CheckBox` / `Toggle` (a Flutter `CheckboxListTile` is an iOS `Switch`). `selected`: Android attribute, iOS `Selected` in `traits`. `focused`: Android only — WebDriverAgent has no focus attribute, so it is absent rather than `false`. `scrollable`: Android attribute; iOS `ScrollView` / `Table` / `CollectionView`. Scrollable containers are always listed, even without text or id, so they can serve as `native_scroll` `within`.
- `native_get_elements` accepts the selector fields (`text`, `textContains`, `id`, `type`) as filters, `clickableOnly`, and `includeForegroundApp` (default `true`; `false` saves a device call). Android `package` per element and an explicit `index` field from the plan were not added: `foregroundApp` already tells a system surface apart, and the tree order is the index.

### Rationale

One shape for both platforms is what lets an agent use the same reasoning everywhere; omitting defaults keeps the output close to its previous size. The label/content split makes a field's identity stable — the selector that typed into it still finds it — and is what iOS already did for labels, so Android was aligned to it rather than the other way round.

### Consequences

- **Behaviour change (Android):** a filled field's `text` is now its label (e.g. `Title`), not its content (`Gęś 2`); a selector on the content must use the label instead, and the content is in `value`. Native fields without a hint fall back to `content-desc`, then the content.
- `native_tap` / `native_enter_text` selectors match `text` only, not `value`.
- iOS keeps off-screen Flutter semantics nodes in the tree with zero-size bounds at (0, 0). They are still listed (they are part of the tree), but [D16](#d16) does not count them as visible.

### Verification

- Fixtures: the API 28 keyboard screen has exactly one focused field and no values; the API 35 native field reports `text` "Type here (native)" and `value` "API 35"; the API 28 home tab is `selected`; on iOS 26 the native field's placeholder and the selected tab's `value="1"` are not reported as values.
- Live through the MCP server, Android API 28 and iOS 18.6 (Testing → Gestures & inspection): the Wi-Fi switch and the terms checkbox report `checked` and change after `native_tap`, "Disabled action" reports `enabled: false`, the Testing tab `selected: true`, the page and the two lists `scrollable: true`; filters (`textContains`, `type`, `clickableOnly`, `includeForegroundApp: false`) return only the matching elements.
- Live, Keyboard screen, both platforms: after `native_enter_text label="Title" text="Gęś"` and appending `" 2"`, the field is `text: "Title"`, `value: "Gęś 2"`; selecting it by `label="Title"` keeps working; after `clear` the value disappears. On iOS this closes the gap noted in [D14](#d14).
- Unit tests cover both parsers (state, field label/value, iOS value types), `scaled` keeping the state, JSON omission of defaults, and the filters.

---

<a id="d16"></a>

## D16 — Scrolling to an element and waiting for one

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_scroll` (target search, `within`, `maxSwipes`), `native_wait_for`; `NativeElement.isVisible`; `NativeConnector.swipe` (`holdMs`).

### Context and dilemma

`native_scroll` with a target swiped up to ten times and then failed, without knowing whether the list had ended; it could only swipe the middle of the screen, not a nested list; and it reported "found" as soon as the target was anywhere in the tree. Live tests on the new example screen showed three more problems:

- On iOS, Flutter keeps off-screen items in the tree as zero-size nodes at (0, 0), so a target far below the fold was "found" after zero swipes.
- `native_scroll` returned while the list was still flinging; the agent then tapped the reported position, and on iOS a tap during scroll momentum only stops the scroll — the button was not pressed and a `native_wait_for` for its effect timed out.
- On iOS one 300 ms swipe moved a list by about 2.4× the finger distance (more than the list's height), so the search skipped over the target and stopped at the end of the list.

Waiting had the same root: agents used fixed sleeps for dialogs and delayed content.

### Options considered

- **Visibility:** trust tree membership; use WDA's `visible` attribute (unreliable: tabs covered by the keyboard report `visible="false"`); or require non-zero bounds.
- **End of list:** a fixed number of swipes; or compare what is visible before and after a swipe.
- **Settling:** a fixed delay after each swipe; or re-read the tree until it stops changing.
- **Momentum:** a quick swipe (fast, but overshoots); a swipe that rests before lifting (removes momentum on Android, only reduces it on iOS: 300 ms + 200 ms rest still moved the content ≈ 1.7× the finger distance); a slow drag with a rest (≈ 0.85–1.2× on iOS).

### Decision

- An element counts as visible only with non-zero width and height (`NativeElement.isVisible`); `native_scroll` and `native_wait_for` ignore invisible matches.
- **Searching swipes are slow drags:** 1 s movement, then the finger rests 300 ms before lifting (`holdMs`). Inside a `within` container a search swipe covers 60% of it by default, so even with iOS's residual momentum the content moves less than one container height and no item is skipped. A plain swipe (no target) stays a quick 300 ms swipe of 400 px, or 80% of a `within` container.
- After every search swipe the tree is re-read until two consecutive reads agree (at most six reads), so the reported state is the settled one.
- **End of list:** if the visible content of the area (texts and positions of visible elements whose center lies in the screen or `within` container) did not change after a swipe, the search stops with "reached the end of the content". Comparing only the container ignores e.g. a clock elsewhere on screen.
- `within` takes a selector of the container (resolved with [D1](#d1) rules); the swipe is centered on it. `maxSwipes` defaults to 10 (max 50). `within` and `startX`/`startY` are mutually exclusive.
- `native_wait_for` polls `getNativeElements` every `intervalMs` (default 500, min 50) until a visible match exists (`state: visible`, returns the element) or none does (`state: gone`), up to `timeoutMs` (default 10 000, max 60 000). On timeout it names the foreground app, because a system surface on top is the usual reason.

### Rationale

Correctness first: a search that silently skips its target, or a "found" that cannot be tapped, is worse than a slower one. The slow drag was measured to be the only variant that stays close to the finger distance on iOS; the 60% share leaves margin for the remaining momentum. Comparing visible content needs no platform knowledge and also catches lists whose end is not reported as an attribute.

### Consequences

- Searching is slower: ≈ 2 s per swipe on Android API 28 and ≈ 2.3 s on iOS 18.6 including the settle reads. In a 60-row list (a row ≈ 25% of the container) reaching row 45 takes about 10 swipes; agents scrolling far should raise `maxSwipes`.
- A swipe that does not move the content (wrong direction at the start of the list, or a swipe in a non-scrollable area) ends the search early with "reached the end" — that is the intended signal to try the opposite direction or a `within` container.
- A plain `native_scroll` may still fling; an agent that taps right after it should read the elements again first (or use a target).
- Off-screen zero-size nodes still appear in `native_get_elements`; `native_tap` on one would tap (0, 0). Tracked in the plan status as a follow-up.

### Verification

- Live through the MCP server, Android API 28 and iOS 18.6, Gestures & inspection screen: scrolling the page to "Show message in 2 s", tapping it and `native_wait_for` "Delayed message" (`visible`, ≈ 2.5–2.9 s) and then `gone` (≈ 4 s) work; a missing element times out naming `com.example.counter`. Before the settle step, the same sequence failed on iOS (tap during momentum).
- `within` the horizontal list: "Chip 17" found going left, "Chip 2" going back right; "Chip 99" stops with "reached the end"; the page itself does not move. `within` the vertical list: "Row 22" (7–8 swipes) and "Row 45" (10 swipes) found on both platforms; "Row 99" stops at the end. Before the slow drag, iOS skipped "Row 30" and "Row 45" and stopped at row 60.
- Off-screen check: on iOS "Show message in 2 s" is listed at (0, 0, 0×0) before scrolling; it is now found only after a swipe.
- Unit tests cover zero-size matches, settling, the slow held drag, end detection (whole screen and container only), the 60% / 80% shares, `maxSwipes`, `within` validation, and every `native_wait_for` path.

