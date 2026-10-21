# Native lane — design decisions

Records of the design decisions behind the native automation lane (`native_*` tools). Each record explains the dilemma, the options that were considered, what was chosen and why, the consequences, and how the decision was verified. Records are never deleted: when a decision changes, its status says so and the record explains what was learned.

Decisions are referenced from the code (`See docs/native-lane-decisions.md#dN`) and from the changelog.

| # | Topic | Status |
| --- | --- | --- |
| [D1](#d1) | Ambiguous element selectors | Accepted |
| [D2](#d2) | Coordinate space of the native lane | Accepted |
| [D3](#d3) | Automatic recovery of a lost session | Accepted |
| [D4](#d4) | Native session model of the CLI | Accepted |
| [D5](#d5) | Heavy SDK views in a separate example app | Proposed (V-09 not started) |
| [D6](#d6) | Screenshot of part of the screen | Accepted |
| [D7](#d7) | Default app for device shortcuts | Accepted |
| [D8](#d8) | Order of the large research topics | Proposed (X-01 / X-02 not started) |
| [D9](#d9) | Granularity of device shortcut tools | Accepted |
| [D10](#d10) | UIAutomator2 local port and server reuse | Accepted |
| [D11](#d11) | Starting and activating apps | Accepted |
| [D12](#d12) | Device operations outside WebDriver | Accepted |
| [D13](#d13) | Bridge from Flutter coordinates to the native lane | Accepted |
| [D14](#d14) | Software keyboard and key presses | Accepted |
| [D15](#d15) | Element state and the label / content of text fields | Accepted |
| [D16](#d16) | Scrolling to an element and waiting for one | Accepted |
| [D17](#d17) | Changing permissions without the system dialog | Accepted |
| [D18](#d18) | UIAutomator2 idle wait | Accepted |
| [D19](#d19) | Android toasts in the tree | Accepted |
| [D20](#d20) | Simulated biometrics | Accepted |
| [D21](#d21) | Opening a notification on iOS | Accepted |
| [D22](#d22) | Flutter lane while system UI covers the app | Accepted |

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


### Follow-up (unit 8, 2026-10-20)

- **Duplicate nodes from WebDriverAgent.** On iOS 26.4 the Face ID system alert (shown over the app by `local_auth`) is listed twice in the WDA page source — identical type, label, id and bounds — so `native_tap text="Cancel"` failed as ambiguous with two identical candidates. `parseWdaSource` now drops elements that are identical in every reported field; elements that differ in anything (another type, or the same label elsewhere on screen) are kept, and their ambiguity still fails with candidates. After the change the alert's "Cancel" is tapped directly. Unit test: two identical nodes become one, the same label at another position stays a separate element.
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

### Follow-up (unit 7, 2026-10-19)

An operation still running when the connector was disposed — a read that `native_wait_for` had stopped waiting for — failed with "connection closed" once shutdown closed the HTTP client. The decorator took that for a lost session and **started a new one after `dispose()`**, launching UIAutomator2's instrumentation again and keeping the MCP server process alive after stdin EOF. A disposed decorator now never re-establishes: such failures, and later calls, end with `NativeNotConnectedException`. Verified: the same sequence now exits immediately; unit test for a failure arriving after dispose.

### Follow-up (unit 10, 2026-10-20): a lost session on a healthy server

`invalid session id` means the server answered and only the session is gone — on Android typically because another client (a CLI session, a second MCP server) took UIAutomator2's single session. Recovery treated it like a lost server: it disposed the connector, which stopped the server it had started, and started a new one; the asynchronous stop of the old instrumentation then killed the new server ("lost again right after re-establishing it", seen live in unit 9). Now, for `invalid session id`, the decorator first asks the connector to **open a new session on the same server** (`NativeConnector.reopenSession`); the server — and ownership of its bootstrap — moves to the new connector, and the old one only drops its lost session. If that fails, the full restart runs as before. A broken connection or an unreachable server still restarts (the server may be gone).

- Live, Android API 35: an MCP server running while a CLI session took its session — both MCP reads succeeded on a reopened session (≈ 0.1 s), and the CLI's next command opened its own again (≈ 0.2 s); no server restart.
- Unit tests: reopen instead of restart for `invalid session id`; fallback to a restart when reopening fails; no reopen for a lost connection; the Android connector's `reopenSession` opens a second session on the same server and hands the bootstrap over.

---

<a id="d4"></a>

## D4 — Native session model of the CLI

- **Status:** Accepted (2026-10-20)
- **Applies to:** `marionette native-*` commands (`marionette_cli`); `AndroidBootstrap` / `IosBootstrap` `detached` mode, `stopServer`; `WebDriverNativeConnector.openSession(sessionId:)` and `release()`.

### Context and dilemma

The MCP server is one long-lived process that holds the device-side server (`adb shell am instrument -w` for UIAutomator2, `xcodebuild test-without-building` for WebDriverAgent) for the whole session. The CLI starts a new process for every command. Starting the server per command takes seconds to a minute and a new WebDriverAgent run can close a visible system alert; tearing it down after every command would make the next one start from scratch. Three assumptions of the plan had to be checked first: that a server started without a holding host process keeps working, that a detached `xcodebuild` survives the CLI and can be stopped by pid, and whether WebDriver sessions expire when idle.

### Options considered

1. Bootstrap per command — simple, but each command costs seconds to a minute and closes alerts.
2. A CLI daemon that holds the servers and proxies commands — works regardless of server behaviour; an extra process, IPC and lifecycle management.
3. Servers detached from the CLI plus a session registry — commands talk to the WebDriver server directly by its saved URL and session id; no extra host process of ours.
4. For the CLI commands themselves: generate them from the MCP tool definitions, or write them by hand like the existing Flutter commands, calling the shared tool handlers.

### Decision

- **Option 3.** `native-connect` starts the server detached and records `{platform, serial | udid, baseUrl, port, sessionId, defaultAppId, pid, startedServer}` in `~/.marionette/native/<name>.json` (atomic write, like the instance registry); `--native-session <name>` selects the entry (default `default`).
  - **Android:** `adb shell am instrument -w …` started with `ProcessStartMode.detached` — the plan's `am instrument` **without** `-w` does not work (below).
  - **iOS:** `xcodebuild test-without-building` started with `ProcessStartMode.detached`.
  - Both record the pid. A server that was already running (MCP server, an earlier session) is reused and marked as not started by the session.
- **Every command attaches** through a bootstrap that only checks `/status` of the saved URL (never starts anything) and **reuses the saved WebDriver session**: `openSession(sessionId:)` checks it with a cheap call (`GET /orientation`) and opens a new one only when the server no longer has it; the new id is saved. At the end the connector is `release()`d — the client closes, the session stays. The app under test (D7) is saved too.
- **`native-disconnect`** deletes the session and, only if the session started the server, stops it: Android `force-stop` of both UIAutomator2 packages, forward removal and the held `adb` process; iOS SIGTERM (then SIGKILL) to `xcodebuild`. A pid is killed only while it still runs the expected command — pids are reused.
- **Commands are written by hand** (`native-tap`, …, one per MCP tool, named like the MCP tool with dashes, options in kebab case) and call the **same handlers** as the MCP tools (`handleNativeTap(context, args)`), so validation, selectors, messages and hints are shared — the existing CLI pattern, where Flutter commands and MCP tools share `VmServiceConnector`. In the native lane most logic lives in the handlers, so they are the shared layer. `native_connect` / `native_disconnect` are replaced by the session commands.
- A server that is no longer reachable (device rebooted) is reported with "run native-connect again"; nothing is restarted implicitly.

### Rationale

Measured: a detached server keeps working for at least 11 minutes with no host process of the CLI; session creation per command would cost about 1.2 s on Android (UIAutomator2 opens a UiAutomation connection per session) and 10–100 ms on iOS, while reusing a session costs one ~0.13 s check. Option 3 needs no daemon and keeps the commands independent processes, as the rest of the CLI. Calling the shared handlers avoids duplicating the native lane's logic, which — unlike the Flutter lane's — lives on the host side.

### Consequences

- A detached server outlives a crashed or killed CLI; `marionette doctor` lists such servers as orphaned (`parent pid 1`, not in any session) with `kill <pid>` as the fix, and as owned when a process (e.g. an MCP server) holds them.
- UIAutomator2 supports one session per device: an MCP server and a CLI session on the same Android device replace each other's sessions. Verified live: the CLI recreates its own and saves it, and since the D10 follow-up an MCP server that reused the CLI's server no longer stops it on exit; since unit 10 the MCP server's recovery opens a new session on the same server ([D3](#d3) follow-up), so both keep working; an action in flight can still be interrupted — `native-connect` warns and the docs recommend one client per Android device at a time. On iOS both work side by side (WebDriverAgent survives session deletes).
- Messages come from the shared handlers; the CLI rewrites tool names (`native_get_elements` → `native-get-elements`) in non-JSON output, and `help-ai` explains that a camelCase argument (`maxSwipes`) is the kebab-case option (`--max-swipes`).
- New MCP tools need a matching CLI command and an entry in `help-ai`, written by hand — as for the Flutter lane.
- The CLI depends on `marionette_mcp` internals (`src/native_service/…`), like its Flutter commands.

### Verification

- **`am instrument` without `-w` (plan's assumption):** the server starts and answers `/status`, but every `POST /session` fails with "Got null UiAutomation from instrumentation" — the `am` process that provides UiAutomation is gone. An earlier test without `-w` that worked for 11 minutes had two stale `adb shell am instrument -w` host processes from earlier MCP runs still alive; without them it fails reproducibly.
- **Detached `adb shell am instrument -w` (Android API 35):** after the starting process exited, the `adb` process ran under `launchd` (ppid 1) and sessions could be created; one session answered every minute for 11 minutes (≈ 0.13–0.15 s per check, no idle expiry).
- **Detached `xcodebuild` (iOS 26.4):** healthy after 13 s, ppid 1 after the starter exited; session create 10–106 ms, page source ≈ 0.15–0.2 s; SIGTERM stopped `xcodebuild` in 2 s, the runner and the port with it.
- **Session per command (Android, measured over 11 minutes):** create ≈ 1.15–1.2 s, source ≈ 0.11–0.13 s, delete ≈ 0.11–0.13 s.
- **CLI live, Android API 35 and iOS 26.4 (compiled `marionette`):** `native-connect` from a clean device 4.4 s (Android) / 7.8 s (iOS); afterwards commands take 0.26–1.5 s each including process start (`native-tap` 0.26–0.5 s on Android, ≈ 1.25 s on iOS). The default app saved by `native-app --app-id` is used by a later `native-app --action activate` without it. `native-disconnect` stopped the held `adb` process, the server on the device and the forward (Android) and `xcodebuild`, WDA and port 8100 (iOS), and removed the entry.
- **Plan acceptance — §3 permission dialogs only from the CLI, two devices at once** (`--native-session pixel` and `iphone`): `native-permissions --action reset --permission camera` → deep link to the permissions screen → `native-scroll` to "Request camera" → `native-tap` → `native-wait-for` the system dialog ("While using the app" / "Allow") → `native-tap` → status "camera: granted" on both platforms.
- **Both lanes from the CLI:** `marionette --uri <vm-service> native-map-flutter-rect --x 0 --y 0 --width 100 --height 50` → `rect` 300×150, scale 3.0, Flutter view 1280×2856 (Android API 35); without `-i` / `--uri` the command is a usage error naming them.
- **Orphaned server:** with the iOS session's registry entry deleted, `doctor` reported "Orphaned WebDriverAgent (pid …)" with `kill <pid>` as the fix; an MCP `native_connect` meanwhile reused that WDA (0.73 s, D10 follow-up); `kill` stopped it.
- **Every command live (compiled CLI, API 35 and iOS 26.4):** gestures on elements and points (`native-tap`, `-double-tap`, `-long-press` → counters +1; `native-pinch` scale 2 → 1.63–1.64, 0.5 → 0.92), `native-swipe` (chips move; iOS edge swipe goes back), `native-scroll` with `--within-type` / `--within-index` both ways and the end-of-list error, text (`native-enter-text` with `--label`, focused, `--clear`, Polish characters; `native-press-key` backspace / home / volume; unsupported keys and the Gboard floating toolbar refused with hints), `native-wait-for` visible / gone, `native-take-screenshot` full (1280×2856 / 1320×2868) and element (1184×288 / 1224×288), `native-device-info`, `native-set-orientation`, `native-set-location`, `native-notifications` open / close / push (title-body and `--payload` JSON; Android push refused with a hint), `native-app` activate / background / terminate / restart, `native-permissions` grant / revoke (termination reported) / reset, `native-biometrics` match / nonMatch / enroll / unenroll (iOS) and the Android enroll hint, `native-map-flutter-rect` with `--uri` on both platforms (rect 72, 900, 300×150 on iOS), `native-connect` twice ("already connected") and with an unknown serial (error, no session saved).
- **Argument mapping:** a unit test parses every option of the 20 tool commands and checks the result equals the tool arguments, with the MCP schema's names and int / double types.
- Unit tests: detached starts on both platforms (pid, `-w`, no second start), `stopServer`, session reuse and replacement, `release` keeps the session; CLI registry, attach / reuse / replacement, missing session and dead server messages, usage errors, `native-sessions`, `native-disconnect` of a reused server, doctor findings.

---

<a id="d5"></a>

## D5 — Heavy SDK views in a separate example app

- **Status:** Proposed — the work it applies to (V-09) has not started.
- **Applies to:** V-09 (§1c: `flutter_stripe` `CardField`, `google_mobile_ads`, a PDF view); a future `example_sdk/` app.

### Context and dilemma

Verifying the native lane on SDK views needs packages with their own requirements (minimum SDKs, Flutter versions, native configuration, keys). The main example app must keep working on the minimum supported Flutter (3.27 — dependencies there are pinned for it, see unit 8) and also serves as the `call_custom_extension` demo.

### Options considered

1. Add the packages to the main example app.
2. A separate example app, `example_sdk/`, with its own `pubspec.yaml`.
3. No repro.

### Decision

Option 2, when V-09 is taken up: a separate app with the same Testing-tab structure and instructions for its test keys.

### Rationale

The main example stays light and within the minimum Flutter version; dependency conflicts stay isolated.

### Consequences

A second app to maintain; it does not join the minimum-Flutter CI job.

### Verification

None yet.

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

<a id="d7"></a>

## D7 — Default app for device shortcuts

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_permissions`, `native_app`, `native_notifications action=push` (`appId`); `NativeServiceContext.defaultAppId`, `isSystemAppId`.

### Context and dilemma

Shortcuts act on an app and need its Android package name or iOS bundle id. Requiring it in every call makes the agent hunt for an identifier it rarely knows; guessing from the current foreground app is wrong exactly when shortcuts are needed — a permission dialog, a picker or the browser is in front.

### Options considered

1. `appId` always required.
2. Default to the current foreground app.
3. Default to the first non-system app seen in the foreground during the session, always overridable.

### Decision

Option 3. The session remembers the first foreground app that is not a system app; that is the default `appId`, and every result names the app it acted on. The foreground app is observed at `native_connect`, in `native_get_elements`, `native_device_info`, a successful `native_wait_for` (only while the default is unknown, so it costs nothing afterwards), and right before a shortcut needs it. An explicit non-system `appId` also becomes the default when none is known — the agent has named the app under test. When nothing is known, the tool fails and asks for `appId`. System apps are recognised by prefix: `com.android.`, `com.google.android.`, common OEM prefixes (`com.samsung.`, `com.sec.android.`, `com.miui.`, `com.xiaomi.`, `com.huawei.`, `com.oppo.`, `com.coloros.`), `android`, and `com.apple.`.

### Rationale

An agent normally connects with the app on screen, so the default is right; option 2 would be wrong in the very situations shortcuts exist for.

### Consequences

- The prefix list needs maintenance; Google apps (e.g. Chrome `com.android.chrome`) count as system, so they can only be targeted with an explicit `appId` — acceptable, since they are never the app under test.
- A session started while a system surface is in front has no default until the app is seen.

### Verification

- Live: sessions started with the launcher, Chrome or a SpringBoard alert in front had no default; the first runs showed that observing only at `native_connect` / `native_get_elements` was not enough (an agent waiting with `native_wait_for` and then calling `native_app` got "pass appId"), which added the observation in `native_wait_for`, before a shortcut, and for an explicit `appId`.
- Unit tests: system prefixes, first app wins, lazy lookup, `native_wait_for` observation, explicit `appId`, reset on disconnect.

---

<a id="d8"></a>

## D8 — Order of the large research topics

- **Status:** Proposed — neither topic has started.
- **Applies to:** X-01 (DOM access in WebViews) and X-02 (physical iPhones).

### Context and dilemma

Both topics are large; there is capacity for one at a time.

### Options considered

1. X-01 first: WebViews are part of everyday flows (sign-in, terms, web payments) and can be worked on with emulators and simulators.
2. X-02 first: physical iPhones are needed for the camera and real biometrics, and for every device shortcut that currently uses `simctl`.

### Decision

Option 1, unless a client project needs physical iPhones sooner.

### Rationale

The native lane already reads and drives WebView content through accessibility (unit 7); DOM access would make it exact. Camera and biometrics are partly covered by simulator shortcuts ([D20](#d20)).

### Consequences

The iOS camera (§1b) and everything listed for iPhones in the physical-device checklist stay unverified until X-02.

### Verification

To do: confirm with client projects that none needs physical iPhones first; if one does, swap the order.

---

<a id="d9"></a>

## D9 — Granularity of device shortcut tools

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_permissions`, `native_app`, `native_notifications`, `native_device_info`, `native_set_orientation`, `native_set_location`, `native_open_url`.

### Context and dilemma

Every MCP tool costs space in the agent's context (name, description, schema). One tool per operation is the clearest schema but multiplies the tool count.

### Options considered

1. One tool per operation (`native_grant_permission`, `native_revoke_permission`, …).
2. Topic tools with an `action` parameter.

### Decision

Option 2: `native_permissions` (grant / revoke / reset), `native_app` (activate / background / terminate / restart), `native_notifications` (open / close / push). Operations with different annotations stay separate: `native_device_info` is read-only, `native_set_orientation` and `native_set_location` change state, `native_open_url` has a single parameter. Invalid `action` × parameter combinations are rejected in the handler before any device call. Biometrics (`native_biometrics`, S-05) is postponed to unit 8, where the example app gets a screen to verify it on. *Done in unit 8: `native_biometrics` with `match` / `nonMatch` / `enroll` / `unenroll` ([D20](#d20)).*

### Rationale

Fewer tools in context; consistent with `native_scroll` (one tool, several modes) and with the read-only annotation that agents and hosts use.

### Consequences

- Dependent parameters must be validated precisely; each combination has a unit test.
- `native_app` has no separate `launch`: on both platforms starting a running app brings back its existing instance ([D11](#d11)), so `activate` covers both; `restart` gives a fresh start.

### Verification

- Unit tests for every action and invalid combination; all tools exercised live on Android API 28, API 35 and iOS 18.6.

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

### Follow-up (unit 9, 2026-10-20): reusing a running WebDriverAgent

The iOS bootstrap has the same fast path as Android — a healthy WebDriverAgent already listening on the port is reused when it serves the requested simulator — but it never matched: it compared `udid` from `/wda/device/info`, and WebDriverAgent 16.15 reports no such field (only `uuid`, a per-app identifier, `AA2E9EB0-…` vs the simulator's `C34D5845-…`). Every running WDA, including one orphaned by an interrupted Marionette process (the deferred item from unit 4), therefore failed `native_connect` with `portConflict`. The check now falls back to the WDA runner app (`com.facebook.WebDriverAgentRunner.xctrunner`) running inside the requested simulator (`simctl spawn <udid> launchctl list`); simulators share the host's network, so only one WDA can listen on the port. A reported `udid` is still trusted first.

- Live, iOS 26.4: with a WDA started outside the MCP server, `native_connect` reused it in 0.75 s (≈ 5 s with a fresh start) and left it running afterwards; before the fix the same call failed with "Port 8100 is already in use by WebDriverAgent attached to a different simulator".
- Unit test: without a reported udid, WDA whose runner runs in the simulator is reused; for another simulator, `portConflict`.
- **Port 8100 taken by another program** (not WebDriverAgent): the bootstrap used to launch WDA anyway and wait 60 s, then failed with "WebDriverAgent did not become ready … retry". It now checks that the port is free before launching and fails at once with `portConflict` and an `lsof` hint (live: 0.9 s instead of 60 s; unit test).

### Follow-up (unit 9, 2026-10-20): a reused UIAutomator2 server must keep its session

**UIAutomator2 10.3.2 stops itself when its current session is deleted** (log: `DeleteSession command` → `Stopping ServerInstrumentation` → instrumentation finished; deleting an unknown session id does not stop it). So a process that reused another process's server (the reuse path above) killed that server when it disconnected: an MCP server that reused the CLI's server stopped it on exit (seen live). This also corrects the verification bullet above ("A second process … left it running on disconnect") for this UIAutomator2 version.

- **Decision:** on Android a connector does not delete its session when its bootstrap reused a server (`SharedServerBootstrap.startedServer == false`); the owner ends the server. `marionette native-disconnect` likewise deletes the session only when its `native-connect` started the server. iOS is unaffected — WebDriverAgent keeps running when a session is deleted.
- **Live after the change (API 35):** an MCP server reusing the CLI's server, then exiting → the CLI's server keeps running and its next command works; a CLI session reusing an MCP server, then `native-disconnect` → "left running".
- **Two clients on one Android device:** UIAutomator2 has a single session, so they take it from each other. A CLI command opens a new session ([D4](#d4)); the MCP server's recovery first failed here — it restarted its server and the old instrumentation's stop killed the new one — and since unit 10 opens a new session on the same server instead ([D3](#d3), follow-up). Both now keep working, but an action of one client can be interrupted when the other takes the session at that moment, so one client per Android device remains the recommendation; `native-connect` warns when it reuses another process's server.
- Unit tests: a session on a shared server is not deleted on dispose, one on an own server is; `native-disconnect` of a reused server sends no `DELETE`.

---

<a id="d11"></a>

## D11 — Starting and activating apps

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_app action=activate|restart`; `NativeDevice.activateApp`.

### Context and dilemma

Returning to the app after a share sheet, browser or Settings must not restart it — the agent's state would be lost. Android offers `monkey` (simple, but meant for random testing) and `am start` (needs the activity name); iOS offers `simctl launch` and WebDriverAgent's `/wda/apps/*`.

### Options considered

- Android: `monkey -p <pkg> -c LAUNCHER 1`; `cmd package resolve-activity --brief` + `am start -n`.
- iOS: WDA `/wda/apps/activate`; `xcrun simctl launch`.

### Decision

- **Android:** `cmd package resolve-activity --brief <pkg>` → `am start -n <activity>`, falling back to `monkey` for unusual manifests; a missing app fails with a hint.
- **iOS:** `simctl launch`; WDA app endpoints are not needed.
- `terminate`: Android `am force-stop`, iOS `simctl terminate` ("found nothing to terminate" is reported as "was not running"). `background`: the Home key through the session.

### Rationale

Both mechanisms are official and predictable, and — verified — bring back the existing instance instead of creating a new one.

### Consequences

- `activate` never restarts a running app; `restart` is the explicit fresh start.
- `terminate` / `restart` end the Flutter lane connection; the results say so.

### Verification

- Android API 28: on the Keyboard screen → Home → `am start -n` printed "Activity not started, its current task has been brought to the front", one activity record in the task, the Keyboard screen kept.
- iOS 18.6: the backgrounded app (pid 55167) on the Keyboard screen came back with the same pid and screen after `simctl launch`.
- Live through the MCP server on API 35 and iOS 18.6: `background` → `activate` returns to the same screen; `restart` starts on Home; `terminate` twice reports "was not running" the second time.

### Follow-up (unit 8, 2026-10-20)

- **`terminate` on Android removes the app's notifications.** `am force-stop` cancels everything the app posted (API 35: 2 notification records before, 0 after), so "terminate, then open the app from its notification" cannot be tested that way; iOS `simctl terminate` keeps them. The result and the description of `native_app` now say so on Android and point to `action=background`. A cold start from a notification works when the system kills a background app (`adb shell am kill`): the notification stays, and tapping it starts the app with the payload.
- Unit test: the Android result mentions the removed notifications and `action=background`, the iOS one does not.

### Follow-up (unit 10, 2026-10-20): deep links during a cold start

A deep link sent right after `restart` (or `activate` of an app that was not running) is lost on Android: the Flutter app has no link handler yet while it starts, so the intent is dropped (seen in units 6 and 8). Reproduced 3/3 on API 35 (`restart` → `native_open_url` → the app stays on Home); with `native_wait_for` on the first screen in between, 3/3 opened the target screen. iOS queues the URL until the app is ready (2/2 worked without waiting). This is app / framework behaviour, so the tools say it: the `native_open_url` description and the Android `restart` result tell the agent to wait for the first screen first. Unit test: the hint is in the Android result only.

---

<a id="d12"></a>

## D12 — Device operations outside WebDriver

- **Status:** Accepted (2026-10-19)
- **Applies to:** `NativeDevice` (`AndroidNativeDevice` on `AdbClient`, `IosNativeDevice` on `SimctlClient`), `NativeConnector.device`, the device shortcut tools.

### Context and dilemma

Shortcuts (permissions, URLs, app lifecycle, location) run through `adb` / `simctl`, not the WebDriver session. Adding them to `NativeConnector` would bloat the interface that is responsible for UI, and its session-recovery decorator.

### Options considered

1. More methods on `NativeConnector`.
2. A separate `NativeDevice` interface reachable through `connector.device`.

### Decision

Option 2. `NativeDevice` covers info, permissions, URLs, app activate / terminate / running state, notification shade, push and location. Operations that need the UI stay on the connector and are combined in the tool layer: `background` presses Home, iOS Notification Center is opened and closed by swipes (no command exists), orientation uses W3C `/orientation`. The iOS device needs the simulator UDID, which the connector takes from `IosBootstrap.resolvedUdid`. The recovering decorator passes `device` through without recovery — it does not use the session. Failures are typed (`NativeOperationFailedException`, `NativeUnsupportedException`) with hints.

### Rationale

Separation of concerns, simple fakes (`FakeNativeDevice`), and the same device operations can later serve the CLI without a WebDriver session.

### Consequences

- iOS shortcuts work on the Simulator only (`simctl`); physical iPhones need X-02.
- iOS Notification Center contents are visible to `native_get_elements` when it is opened over the home screen (SpringBoard is the active app), but not when opened over the app — WebDriverAgent keeps reporting the app's tree; a screenshot shows them.

### Verification

- Endpoints / commands verified before implementation: `pm grant|revoke`, `pm clear-permission-flags` (present on API 35; absent on API 28 and — unit 10 — on API 29; API 30–34 not checked, the tool detects it at run time), `cmd package resolve-activity`, `am start`, `cmd statusbar expand-notifications|collapse` (API 28, 35), `pidof`, `adb emu geo fix` ("OK"); `simctl privacy` (services listed by Xcode 26.4; `camera` accepted although unlisted, `notifications` fails, `photos` recorded but ignored by the full-access Photo Library API, `grant all` partial on iOS 26.4 — see [D17](#d17)), `simctl openurl|launch|terminate|push|location`, `launchctl list` inside the simulator; W3C `/orientation` on UIAutomator2 and WebDriverAgent (screen size and bounds follow the rotation).
- Live through the MCP server on Android API 28, API 35 and iOS 18.6: device info, deep link `marionette-example://app/testing/gestures` (cold and warm start; iOS asks "Open in …?" first), https URL in the browser and back with `activate`, notification shade open / close (Android shade contents in the tree), iOS push with Polish characters visible as a banner and in Notification Center, orientation in both directions, location accepted.
- iOS Notification Center: the first close gesture (swipe up in the middle) only scrolled the list; closing now swipes up from the bottom edge. Rotation is refused while Notification Center is in front ("Unable To Rotate Device"); that error is now typed with a hint to close it.
- Unit tests for both devices on scripted processes, all tools on fakes.

---

<a id="d13"></a>

## D13 — Bridge from Flutter coordinates to the native lane

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_map_flutter_rect`; `marionette.getViewMetrics` in `marionette_flutter`; `VmServiceConnector.getViewMetrics`, `NativeServiceContext.flutterViewMetrics`.

### Context and dilemma

Some targets are invisible to both trees — a camera preview, a map without accessibility, a video surface — but the widgets around them (or hosting them) are known to the Flutter lane. The Flutter lane reports logical pixels of the Flutter view, the native lane screenshot pixels of the device ([D2](#d2)); mixing them by hand is the classic agent mistake (a 2.75× or 3× error). Converting needs the view's pixel ratio and its position on screen, which no single lane knows.

### Options considered

1. Let the agent multiply by a ratio it reads somewhere.
2. Derive the ratio natively (Android `wm density`, iOS display scale) and assume the view starts at (0, 0).
3. A dedicated tool combining both lanes: the Flutter view's logical size from a new extension, its position and size on screen from the native tree.

### Decision

Option 3. `marionette.getViewMetrics` returns the implicit view's `devicePixelRatio`, physical size, logical size and padding. `native_map_flutter_rect` (`x`, `y`, optional `width`/`height` in Flutter logical pixels) finds the Flutter view in the native tree — Android: the app's `android:id/content` container (the FlutterView fills it and reports itself only as a `FrameLayout`; the largest one wins so a dialog's own content does not), iOS: the application element — and maps with scale = native view size ÷ logical view size plus the view's offset. It returns `rect`, `center`, `scale` and the view it used. Notes are added when the view is not found (then it assumes (0, 0)), when the native size differs from Flutter's physical size by more than 4 px, or when the center falls outside the screen. The tool is read-only and needs both `connect` and `native_connect`.

### Rationale

One tested conversion instead of arithmetic in the agent's head; the scale comes from the actual on-screen view, so it also holds if the two lanes disagree about density, and the size check catches split-screen or embedded views.

### Consequences

- The Flutter lane must be connected; the binding version check already guarantees the extension exists.
- Only the implicit (first) Flutter view is supported — enough for apps without multi-view.
- The tool converts coordinates; finding the target is still up to the agent (e.g. the area between two known widgets around a camera preview).

### Verification

- Android API 35 (scale 3.0, view 1280×2856 at (0, 0)) and iOS 26.4 (scale 3.0, view 1320×2868): the Flutter `Text` "Double tap here" mapped to centers (640, 1896) and (660, 1986) — exactly the centers of the same widget's native nodes (48 + 1184/2, 1752 + 288/2 and 48 + 1224/2, 1842 + 288/2); a native double tap at the mapped point incremented the counter, read back through the Flutter lane.
- Android API 28 with a 3-button navigation bar (Flutter view 1080×2028 at (0, 0) on a 1080×2160 screen, scale 2.75): the mapped "Double tap here" text starts at y = 1661 px and its container at 1584 px, as in the native tree (whose node is clipped by the tab bar); the "Settings" tab label maps to x = 945, the native button's center. A native double tap and a native tap at the mapped points incremented the counter and switched to the Settings tab.
- Camera preview on the Android emulator renders (screenshot) but is in neither tree, which is the case this tool exists for.
- Unit tests: the mapping (scale and offset), view detection on both platforms, missing / mismatched view and off-screen notes, missing Flutter lane; `viewMetricsOf` in `marionette_flutter`.

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

### Follow-up (unit 8, 2026-10-20)

- **Gboard's floating toolbar.** With a hardware keyboard attached (the emulator's default `hw.keyboard=yes`), Gboard shows only a small floating toolbar instead of the keyboard, and `dumpsys input_method` still reports `mInputShown=true`. Back does **not** close that toolbar: it reaches the app — on the native screen of the example app it closed both the IME and the Activity. `hideKeyboard` now measures how much of the IME window the keyboard covers (`dumpsys window`: the window's requested height `h` and `mGivenContentInsets` top `T` → (h − T) / h; a full keyboard covers about 40 % — API 28, 1215 of 2028 px inset — while the toolbar reports no cover at all: inset 2700 of 2700 px on API 35) and below 10 % fails with a hint (unfocus the field in the app, or start the emulator with `hw.keyboard=no`) instead of pressing Back. Unknown coverage (the window not found) keeps the old behaviour.
- Verified live on Android API 35 (native screen of the example app, field focused, toolbar shown): `native_hide_keyboard` fails with the hint in 0.2 s and the native screen stays open. The on-screen keyboard path is unchanged (unit-tested; API 35 here always shows the toolbar). Unit tests cover the coverage parser and the guard.


### Follow-up (unit 10, 2026-10-20): a field that changes before typing

`native_enter_text` with a selector sometimes failed although the field was there: on iOS right after a deep link the screen was still moving and WebDriverAgent reported "The previously found element … is not present in the current view anymore" (`stale element reference`); on Android a set-text action was once refused (`invalid element state`, deferred since unit 5). In both cases nothing was typed. The tool now waits 300 ms, finds the field again with the same selector and types once more; a second failure of this kind becomes a typed error with a hint to wait until the screen has settled. Seen live in the E2E runs on iOS 26.4: two of five runs needed the retry and passed. Unit tests: each of the three errors is retried once, a second one fails with the hint, other errors are not retried.

### Follow-up (acceptance tests, 2026-10-21): the iOS Back hint

The hint for `back` on iOS suggested `native_scroll direction=right startX=1 …`. Followed literally, that swipe covers the tool's default 400 px — about 30 % of the screen width on iOS 26.4 (iPhone 17 Pro Max, 1320 px) — and iOS cancels the interactive pop, while the tool reports success. The hint now names `native_swipe` from `startX=1` to about 70 % of the screen width; live, a swipe from (1, 1434) to (924, 1434) returned to the previous screen. `native_scroll` with `startX` / `startY` also reported "from screen center"; it now reports the start point. Unit tests: the hint names `native_swipe` and the 70 % distance; a scroll with an explicit start reports it.
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


### Follow-up (unit 10, 2026-10-20): the label of a focused field on iOS

A focused Flutter text field on iOS reports its hint as a second line of the label (`Title` becomes `Title\nSingle line — keyboard shows Done`), so the exact `label` of `native_enter_text` stopped matching the field it had just focused — the retry above then failed with "No native element with text=\"Title\"". The `label` selector now also matches the first line of an element's text; the exact `text` of the other tools is unchanged (use `textContains` to read such a field). Unit test: a focused field is found by its label, a plain `text` selector stays exact. Verified in three E2E runs on iOS 26.4.
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
- Off-screen zero-size nodes still appear in `native_get_elements`; `native_tap` on one would tap (0, 0). Tracked in the plan status as a follow-up. *Follow-up (2026-10-19): selectors of every tool now match only visible elements — a target that exists only off screen fails with a hint to `native_scroll` to it — and `native_get_elements` leaves zero-size nodes out, so `index` counts what is listed ([D1](#d1)).*

### Verification

- Live through the MCP server, Android API 28 and iOS 18.6, Gestures & inspection screen: scrolling the page to "Show message in 2 s", tapping it and `native_wait_for` "Delayed message" (`visible`, ≈ 2.5–2.9 s) and then `gone` (≈ 4 s) work; a missing element times out naming `com.example.counter`. Before the settle step, the same sequence failed on iOS (tap during momentum).
- `within` the horizontal list: "Chip 17" found going left, "Chip 2" going back right; "Chip 99" stops with "reached the end"; the page itself does not move. `within` the vertical list: "Row 22" (7–8 swipes) and "Row 45" (10 swipes) found on both platforms; "Row 99" stops at the end. Before the slow drag, iOS skipped "Row 30" and "Row 45" and stopped at row 60.
- Off-screen check: on iOS "Show message in 2 s" is listed at (0, 0, 0×0) before scrolling; it is now found only after a swipe.
- Unit tests cover zero-size matches, settling, the slow held drag, end detection (whole screen and container only), the 60% / 80% shares, `maxSwipes`, `within` validation, and every `native_wait_for` path.

### Follow-up (unit 7, 2026-10-19)

- **iOS off-screen elements with real coordinates.** WebDriverAgent lists a WebView's whole page, e.g. "Section 2" at y = 4851 px on a 2868 px screen; the zero-size rule did not catch it, so a search would have reported it as found. `parseWdaSource` now keeps only elements that overlap the application element (the screen) and clips partly visible ones to it — as UIAutomator does — so the center is always on screen. A clipped element no longer matches WDA's geometry XPath, so lookups for typing / element screenshots fall back to id or label for it. An element covered by another one (a photo under the picker's toolbar) is still considered visible: the tree does not say what is on top.
- **End of content needs two unchanged swipes.** In a WebView page with a 900 px empty block, one swipe inside the block left the visible tree identical (only the block, clipped to the viewport) although the page moved, and the search stopped with "reached the end". The end is now reported after two consecutive swipes without a visible change; a real end costs one extra swipe (verified on Android and iOS: the search crosses the block, a missing target still stops at the end).
- **`native_wait_for` honours `timeoutMs`.** The loop checked the deadline only between reads, so one slow read could stretch the wait: a read takes up to 10 s on an Android screen that never goes idle without [D18](#d18), and 3–4 s next to iOS system pickers. Each read is now limited to the remaining time; if no read finished at all the error says so, otherwise it is the regular "not found within …". (An 8 s wait that once returned after 259 s was the Mac going to sleep — macOS power log: idle sleep 19:14:45–19:19:05 — not the device; nothing in the tool can prevent that.)
- **Sheets.** On iOS a downward swipe (`native_scroll direction=down`) while a sheet's content is already at its top dismisses the whole sheet (seen in the photo picker) — a native gesture, not a bug; inside sheets, search in the direction of unseen content.

### Follow-up (unit 10, 2026-10-20): slow reads next to iOS system pickers

Reads with `UIDocumentPicker` open took 2.6–2.7 s each (75 KB page source) against 0.17 s on an app screen (10 KB), so a search in the picker takes tens of seconds. Measured on iOS 26.4 with WebDriverAgent's settings: waiting is not the cause — `waitForIdleTimeout` 0 and `animationCoolOffTimeout` 0 gave the same 2.7 s; a smaller `snapshotMaxDepth` (25 instead of 50) gave 2.0 s but can drop deep elements of real apps. The cost is the accessibility snapshot of the picker, a view of another process. **Decision:** keep the defaults and document it; searches in pickers are slow but correct. (Analogy to [D18](#d18) does not hold: there the cost was a wait, here it is the snapshot itself.)

### Follow-up (acceptance tests, 2026-10-20): a target a lazy list has not built

The hint to scroll was given only for a target that exists off screen. In a lazy list (Flutter `ListView.builder`, Android `RecyclerView`) a far item is not in the tree at all — on the Gestures & inspection screen "Row 40" was absent on both platforms, not even as a zero-size node — so `native_tap text="Row 40"` only said to call `native_get_elements`. When nothing matches and a scrollable container is on screen, the hint now also suggests `native_scroll` with the same selector as the target. Unit test: a miss on a screen with a scrollable container hints to scroll, a miss on a screen without one does not. Live on Android API 35 and iOS 26.4: `native_tap text="Row 40"` before scrolling names `native_scroll`.

---

<a id="d17"></a>

## D17 — Changing permissions without the system dialog

- **Status:** Accepted (2026-10-19)
- **Applies to:** `native_permissions`; `NativeDevice.setPermission`, `androidPermissionNames`, `iosPrivacyService`.

### Context and dilemma

A test often needs a known permission state (granted, denied, or "never asked") before it starts, and an agent may want to skip a dialog. Both platforms have commands for it, with traps found while verifying them:

- `pm reset-permissions -p <pkg>` from the plan does not exist: the command takes no package (API 28 and 35 help: "Revert all runtime permissions to their default state") and silently resets **every app** on the device.
- `pm revoke` kills the app's process; most `simctl privacy` changes terminate the iOS app too. The Flutter lane loses its connection.
- Permission groups have different names per platform and API level (photos: `READ_EXTERNAL_STORAGE` before API 33, `READ_MEDIA_*` after; notifications need no permission before API 33). `pm grant` of a permission the app does not declare fails.
- Xcode 26.4's `simctl privacy` cannot change notifications.
- `simctl privacy grant photos` records the app as allowed (`kTCCServicePhotos = 2` in the simulator's TCC database), but the full-access Photo Library API of iOS 14+ ignores it: the app still shows the "full access" dialog (seen on iOS 18.6 and 26.4).
- `simctl privacy grant all` on iOS 26.4 grants only some services (location, in the example app); `reset all` resets all of them.

### Options considered

- Reset on Android: (a) `pm reset-permissions` (global); (b) `pm clear` (wipes app data); (c) `pm revoke` + `pm clear-permission-flags <pkg> <perm> user-set user-fixed`.
- Names: platform names in the tool, or one shared set mapped per platform.
- App termination: ignore, document only, or detect and report.

### Decision

- One shared set: `camera`, `microphone`, `photos`, `location`, `contacts`, `calendar`, `notifications`, `all`. Android maps each to its permissions for the device's API level and changes only those the app declares (from `dumpsys package`); none declared → an error naming the missing manifest entries. iOS maps to `simctl privacy` services (`camera` works although its help does not list it).
- **Reset on Android** is option (c): revoke, then clear the flags that record "user set" / "don't ask again", so the app asks again. Where the command is missing (API 28 and 29, checked in unit 10; API 30–34 not checked) the permission is revoked and the result explains that a "don't ask again" choice cannot be undone without reinstalling.
- Unsupported combinations fail with a hint: notifications before API 33 ("nothing to change"), notifications on the iOS Simulator and grant / revoke of photos on iOS ("answer the dialog with `native_tap`", e.g. "Allow Full Access"); reset of iOS photos works.
- On iOS, grant / revoke of `all` changes camera, microphone, location, contacts and calendar one by one and notes that photos and notifications were skipped; reset of `all` uses `simctl privacy reset all`.
- The tool checks whether the app was running before the change and is not after it (`pidof`; `launchctl list` in the simulator) and then says the change terminated it and that the Flutter lane must reconnect.

### Rationale

Option (c) is the only per-app reset that keeps app data. Detecting termination turns a confusing "Flutter connection lost" into an explained, expected effect.

### Consequences

- Without `clear-permission-flags` (API 28, 29; API 30–34 not checked) a full reset needs a reinstall (stated in the result).
- Libraries may interpret groups differently: on API 28, `permission_handler` reports `Permission.photos` as denied even after `photos` (`READ_EXTERNAL_STORAGE`) is granted, because before Android 13 it maps photos to storage; the tool changes the platform permission, not a library's view.
- A system permission alert stays on screen after its app has been terminated by a change (seen on iOS); the agent has to dismiss it.

### Verification

- Android API 35: after "Don't allow" twice the app no longer showed the dialog (flags `USER_SET|USER_FIXED`); after `reset` the dialog appeared again; after `grant` no dialog and the status was "granted"; `revoke` reported that it terminated the app. Reset of a permission that was not granted does not kill the app, and the tool reports no termination.
- Android API 28: `reset` revokes and returns the explanation; `notifications` → unsupported with hint; `location` (not in the manifest) → manifest error.
- iOS 18.6: `grant camera` → status "granted", no dialog; `reset camera` → app terminated (reported), dialog shown again; `notifications` → unsupported with hint; `reset all` works.
- iOS 26.4 (iPhone 17 Pro Max), Device & permissions screen: `reset all` → every group "denied" and "Request contacts" shows the dialog again; `grant all` (service by service) → camera, microphone, location, contacts, calendar "granted"; `grant photos` → unsupported (a "Request photos" tap after `simctl privacy grant photos` still showed "Limit Access… / Allow Full Access / Don't Allow"); `revoke camera` → "permanentlyDenied". Before the per-service change, `grant all` granted location only.
- Android API 35, Device & permissions screen: `grant all` → camera, microphone, photos, location, contacts, calendar "granted" ("photos (storage)" stays denied: `READ_EXTERNAL_STORAGE` is declared up to API 32 only); `reset all` → all "denied", "Request location" shows the dialog again.
- Unit tests: mapping per API level, declared-permission filtering, reset with and without flag clearing, never `reset-permissions`, typed failures, termination reporting.

---

<a id="d18"></a>

## D18 — UIAutomator2 idle wait

- **Status:** Accepted (2026-10-19)
- **Applies to:** `AndroidNativeConnector.connect` (`waitForIdleTimeout` setting), every Android read and action.

### Context and dilemma

Before each tree read and action, UIAutomator2 waits until the UI has been idle, for at most `waitForIdleTimeout` — 10 000 ms by default. On a screen with continuous animation (a playing video, a map, a picker loading thumbnails) the UI is never idle, so **every** read took the full 10 s; one `native_get_elements` on the video screen took 10.1 s, and a search or wait doing several reads took a minute or more. Lowering the wait risks reading the tree in the middle of a screen transition. (A 259 s `native_wait_for` seen while investigating was the host Mac sleeping, not this setting — see the [D16](#d16) follow-up.)

### Options considered

Measured on the video player screen (Android API 35, video playing), three reads each:

| `waitForIdleTimeout` | Read time |
| --- | --- |
| 10 000 ms (default) | 10 121, 10 074, 10 084 ms |
| 1 000 ms | 1 083, 1 093, 1 104 ms |
| 0 ms | 16, 15, 13 ms |

### Decision

Set `waitForIdleTimeout` to **500 ms** right after the session is created (`POST /session/{id}/appium/settings`). Failing to set it is logged and does not fail the connect.

### Rationale

On static screens the setting changes nothing — the wait ends as soon as the UI is idle. 500 ms still waits out ordinary transitions (~300 ms), so a read right after navigation sees the new screen; 0 would read mid-animation. Scroll searches compare consecutive reads ([D16](#d16)), so they tolerate a shorter wait.

### Consequences

- On continuously animating screens each read costs ~0.5 s instead of 10 s.
- A transition longer than 500 ms can be read mid-way; tools that act on a target found that way may need `native_wait_for` first.
- The value is set again for every session, including one re-established by [D3](#d3). *Verified in unit 10:* settings belong to the session, not the server — a new session of another client on the same running server reports the default `waitForIdleTimeout` of 10 000 ms, so nothing leaks to other tools.

### Verification

- After the change, reads on the playing video screen take ~0.55–0.6 s through the MCP server; `native_wait_for` there finds an element in 0.6 s.
- Re-measured later on API 35 after ruling out the host sleeping: playing video — 10 046 / 8 982 / 10 115 ms with the default, 576 / 602 / 609 ms with 500 ms; a static screen — 22 / 18 / 21 ms vs 15 / 16 / 14 ms (no difference).
- Unit test: the session posts `{"settings": {"waitForIdleTimeout": 500}}`.

---

<a id="d19"></a>

## D19 — Android toasts in the tree

- **Status:** Accepted (2026-10-20)
- **Applies to:** `AndroidNativeConnector.getNativeElements` (every Android read: `native_get_elements`, selectors, `native_wait_for`, `native_scroll`); `NativeElement.isToast` / `isListed`; `selectElement`.

### Context and dilemma

While a `Toast` is on screen (Android API 35, example app → Notifications → "Show Android toast"), every UIAutomator2 page source fails with HTTP 500 "Cannot set AccessibilityNodeInfo's field 'mSealed'". The toast itself is never in the tree: neither during nor after it, nor with UIAutomator2's `enableMultiWindows` setting, which lists the other windows but not the toast. A long toast lasts 3.5 s, a short one 2 s; any tool that reads the tree in that time failed with a raw WebDriver error.

On API 28 the same moment looks different: UIAutomator2 logs "Adding toast message to root: …" and **adds** the toast to the page source as `<android.widget.Toast class="android.widget.Toast" text="…" displayed="true"/>` — with the wrong package (`com.android.settings`) and **without bounds**. The parser kept it as a zero-size element, which the off-screen rule ([D16](#d16)) then hid. The logcat line next to it ("Accessing hidden field …mSealed (light greylist, reflection)") shows the mechanism: UIAutomator2 builds the node by reflection on a hidden field, which API 28 still allows and API 35 blocks — hence the 500.

### Options considered

1. Pass the error through (the agent retries).
2. Retry the read inside the connector for at most the length of a long toast, then fail with a hint.
3. Turn on `enableMultiWindows` — rejected: it does not make the toast visible and does not stop the failure.
4. For API 28: hide the boundless toast node (as before), or list it as a read-only element.

### Decision

Option 2. An Android read that fails with the `mSealed` message is retried every 500 ms for up to 5 s; after that the tool fails with `NativeOperationFailedException` explaining that a toast is probably on screen, that this Android version cannot list it, and that `native_take_screenshot` shows it. Other errors are not retried here ([D3](#d3) handles a lost session).

Where UIAutomator2 does add the toast (API 28), it is **listed read-only**: `native_get_elements` and `native_wait_for` (visible and gone) include an `android.widget.Toast` element with `0×0` bounds, while selectors of acting tools never pick it — a tap targeted at it fails with "It is a toast: it can be read … but not tapped".

### Rationale

A toast is short and disappears on its own, so waiting it out is invisible to the agent apart from the time it takes; failing would make every action right after a toast flaky. Where the text is available it is the cheapest and most reliable check ("was the 'Saved' toast shown?"), so it is listed; it has no position, so acting on it is refused with an explanation instead of tapping (0, 0). Elsewhere the screenshot is the only way, so the hint names it.

### Consequences

- A read during a toast takes up to ~3.5 s instead of failing.
- On API 35 toast text can only be checked visually (`native_take_screenshot`); on API 28 and 29 it is readable as text (API 29 checked in unit 10: listed in 26 ms, gone after 2.8 s, no read failure). Which of API 30–34 behave which way is unverified (physical devices: checklist).
- Android heads-up notification banners are not in the UIAutomator2 tree on API 35 (the notification is readable in the shade, `native_notifications open`).
- The listed toast has `0×0` bounds and the wrong package; consumers must not use its position.

### Verification

- Live, Android API 35: a `native_get_elements` right after "Show Android toast" returned the tree after 3.6 s (before the change: HTTP 500); the screenshot shows the toast. After the read-only listing was added: unchanged (3.9 s, no toast element).
- Live, Android API 28 (Pixel 3 emulator): reads during the toast take ~0.1 s (no failure); `native_wait_for textContains="Native toast"` → visible in 0.5 s (`android.widget.Toast`, 0×0); `native_get_elements` lists it; `native_tap` on it fails with the toast hint; `native_wait_for … state=gone` → gone after 3.3 s. Before the change the toast was not listed.
- Unit tests: the read is retried until the toast is gone, gives up after the window with a typed error carrying the toast hint, and other server errors are not retried; the parser keeps the boundless toast node; `native_get_elements` lists it; `native_wait_for` finds it and waits until it is gone; a selector refuses it with the toast hint.

---

<a id="d20"></a>

## D20 — Simulated biometrics

- **Status:** Accepted (2026-10-20)
- **Applies to:** `native_biometrics`; `NativeDevice.biometrics`, `NativeBiometricAction`; `SimctlClient.notify`.

### Context and dilemma

A biometric prompt (Face ID, Touch ID, `BiometricPrompt`) is system UI that a test cannot answer by tapping: it waits for a face or a finger. The simulator and the emulator can fake both, through different mechanisms, and enrollment works very differently:

- **iOS Simulator:** the "Features → Face ID / Touch ID" menu posts Darwin notifications, which `simctl spawn <udid> notifyutil` can post too: `com.apple.BiometricKit.enrollmentChanged` with state 1 / 0 (enrolled / not), and `com.apple.BiometricKit_Sim.pearl.match` / `.nomatch` (Face ID) or `.fingerTouch.match` / `.nomatch` (Touch ID).
- **Android emulator:** `adb emu finger touch <id>` simulates a finger with a given id. Enrollment needs a screen lock (`locksettings set-pin`) and the Settings enrollment wizard, which itself waits for finger touches; there is no command that enrolls directly. Physical devices offer neither.

### Options considered

1. One tool with `action`: `match`, `nonMatch`, `enroll`, `unenroll` (consistent with [D9](#d9)).
2. Separate tools per action — more tools in context for a rarely used feature.
3. Automate Android enrollment inside the tool (set a PIN, drive the Settings wizard) — fragile across API levels and OEM Settings, changes the device's lock screen without the user's consent.

### Decision

Option 1. iOS: `enroll` / `unenroll` post `enrollmentChanged` with state 1 / 0; `match` / `nonMatch` post both the Face ID and the Touch ID notification (the device has only one of them; the other is ignored). Android (emulator only): `match` touches finger 1, `nonMatch` finger 2; `enroll` / `unenroll` fail with `NativeUnsupportedException` and a hint describing the manual steps (`adb shell locksettings set-pin 1111`, then the Settings fingerprint wizard, answering its prompts with `native_biometrics match`). On a physical Android device every action is unsupported with a hint; iOS device operations work on the Simulator only (physical iPhone: X-02).

### Rationale

The prompt is the thing under test; faking the sensor is the only way to answer it. Android enrollment is a one-time device setup with side effects (a PIN), so it stays manual but documented in the result.

### Consequences

- A test must first enroll on iOS (state is kept by the simulator) or prepare the Android emulator once (fingerprint 1 enrolled; finger 2 never enrolled, so it is a reliable non-match).
- iOS state persists across app reinstalls and sessions; `unenroll` makes `local_auth` report "no biometrics enrolled".

### Verification

- Live, iOS 26.4 (iPhone 17 Pro Max), Auth screen: `unenroll` → "enrolled: false"; `enroll` → "enrolled: true"; "Authenticate" shows the Face ID prompt; `match` → "Biometric result: success"; `nonMatch` → "Face Not Recognised" alert, its "Cancel" → "UserCancelled".
- Live, Android API 35 emulator: after `locksettings set-pin 1111`, the Settings wizard enrolled a fingerprint with `native_biometrics match` answering its touches; the app's `BiometricPrompt` appears in the tree; `match` → success; `nonMatch` → "Not recognized" in the prompt; Back → failed. `enroll` returns the hint.
- Unit tests: notifyutil arguments per action, emulator finger ids, enroll hint, the action passed by the tool, and rejection of an unknown action.

---

<a id="d21"></a>

## D21 — Opening a notification on iOS

- **Status:** Accepted (2026-10-20)
- **Applies to:** `native_notifications` (iOS result text and description); agent instructions.

### Context and dilemma

On the iOS Simulator (26.4 and 18.6) a tap on a notification in the Notification Center (the cover sheet that `native_notifications open` pulls down) does not open the app. SpringBoard's log for the tap: "Notification cell tap performing default action … Hinting side swipe instead of executing action … didExecute? NO". This happens with and without Face ID enrolled, with a WDA element tap and with a coordinate tap, and for both buttons that represent the notification (`ListCell`, `ShortLook.Platter.Content.Seamless`). A tap on the **banner** over the home screen opens the app. A swipe right across the notification in the Notification Center opens it as well.

### Options considered

1. Make `native_tap` swipe when the target is a notification cell — hidden behaviour in a generic tool.
2. Add an `open` action with a selector to `native_notifications`.
3. Document the gesture: in the tool description and in the iOS result of `action=open`.

### Decision

Option 3: the description says that a notification is opened with `native_tap` on Android and on an iOS banner, and with a swipe right (`native_swipe` across its bounds) in the iOS Notification Center; the iOS result of `open` repeats it.

### Rationale

The gesture is a platform behaviour, works with existing tools and is now discoverable where the agent reads notifications. A dedicated action can still be added if agents keep tapping.

### Consequences

- Agents must use different gestures for the same thing on the two platforms; the text says so where it matters.
- Opened over a foreground app, the Notification Center is not in the WebDriverAgent tree (the app's elements are returned instead, seen on iOS 26.4); over the home screen it is. The iOS result of `open` therefore also tells the agent to send the app to the background first.
- Not specific to iOS 26: iOS 18.6 behaves the same. iOS 18.6 also collapses the list into a "1 Notification" button at the bottom of the cover sheet; it must be tapped to expand the list — the iOS result says so. Whether a physical iPhone behaves the same is unverified (checklist; the cover sheet is the lock screen, where a real device asks to unlock).
- Simulated push (`action=push`): the banner appears only when the app is already suspended. Pushed while the app is active — in front, or within about a second after `native_app action=background` — the app's notification delegate decides, and the example app's plugin shows nothing. The push result tells the agent to background the app a few seconds before pushing.

### Verification

- Live, iOS 26.4: banner tap → "Opened from notification: demo-payload"; Notification Center tap → nothing (log above); swipe right from x = 200 to 1100 across the notification → the app opens with the payload — also from a terminated app (cold start).
- Live, iOS 18.6 (iPhone 16 Pro Max): "1 Notification" tapped to expand; tap on the notification → the same "Hinting side swipe" log; swipe right → the app opens with the payload.
- Live, iOS 26.4, push: pushed 3 s after `background` → banner, tap → the app in front; pushed 0.5 s after `background` or in front → nothing shown.
- Unit test: the iOS result contains the swipe hint, the Android one does not.

---

<a id="d22"></a>

## D22 — Flutter lane while system UI covers the app

- **Status:** Accepted (2026-10-20)
- **Applies to:** `marionette.interactiveElements` (`marionette_flutter`), `get_interactive_elements` (MCP) and `marionette get-interactive-elements` (CLI); `coveredAppWarning`.

### Context and dilemma

While a dialog, the notification shade, a biometric prompt, a browser or another native screen covers the app, `get_interactive_elements` still lists the Flutter widgets underneath as if they were reachable (checked for every kind of system UI in unit 8). An agent that only uses the Flutter lane taps them and nothing happens. The widget tree cannot know what is on top; the app's lifecycle state can, partly.

### Options considered

1. Only document it in the agent instructions.
2. Report the app lifecycle state with the elements and warn when it is not `resumed`.
3. Ask the native lane for the foreground app on every Flutter call — couples the lanes and needs a native session.

### Decision

Option 2. The binding adds `appLifecycleState` (`WidgetsBinding.lifecycleState`) to the `marionette.interactiveElements` response; when it is not `resumed`, the MCP tool and the CLI command put a warning first: the app is not in front, system UI or another screen covers it, the widgets may not be reachable — check `native_get_elements`. When `resumed`, nothing is claimed. An older binding sends no state and gets no warning.

### Rationale

The state is free to read and exact for the cases it covers; a warning where the agent reads the elements beats an instruction it may not apply. Claiming "not covered" on `resumed` would be wrong on iOS (below), so only the positive signal is used.

### Consequences

- iOS views presented inside the app's process — a `UIAlertController` shown by the app, the `ASWebAuthenticationSession` sheet — leave the app `resumed`, so they get no warning; the agent instructions cover them.
- The binding's response grows by one field; tools that read the extension directly see it.

### Verification

Live through MCP, lifecycle state with each kind of system UI open:

| System UI | Android API 35 | iOS 26.4 |
| --- | --- | --- |
| none | resumed | resumed |
| alert from the app (`AlertDialog` / `UIAlertController`) | inactive | **resumed** |
| permission dialog / alert | inactive | inactive |
| native screen (Activity / full-screen view controller) | paused | paused |
| notification shade / Notification Center | inactive | inactive |
| biometric prompt | inactive | inactive |
| browser sign-in (Custom Tab / consent alert / auth sheet) | paused | inactive / **resumed** |
| back in the app | resumed | resumed |

- With the Face ID prompt open, `get_interactive_elements` starts with "Warning: the app is not in front (lifecycle: inactive) …"; without it, no warning.
- Unit tests: warning for `inactive` / `paused` / `hidden`, the CLI's command name, none for `resumed` or a missing state.

