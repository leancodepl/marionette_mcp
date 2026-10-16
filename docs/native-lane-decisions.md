# Native lane — design decisions

Records of the design decisions behind the native automation lane (`native_*` tools). Each record explains the dilemma, the options that were considered, what was chosen and why, the consequences, and how the decision was verified. Records are never deleted: when a decision changes, its status says so and the record explains what was learned.

Decisions are referenced from the code (`See docs/native-lane-decisions.md#dN`) and from the changelog.

| # | Topic | Status |
| --- | --- | --- |
| [D3](#d3) | Automatic recovery of a lost session | Accepted |
| [D10](#d10) | UIAutomator2 local port and server reuse | Accepted |

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
