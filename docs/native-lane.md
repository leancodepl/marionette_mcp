# Native lane

Marionette drives a Flutter app through two lanes:

- the **Flutter lane** (`connect`, `tap`, `get_interactive_elements`, …) talks to the app over the VM service and sees the widget tree;
- the **native lane** (`native_*` tools, `marionette native-*` commands) talks to the platform's UI automation server — **UIAutomator2** on Android, **WebDriverAgent** on the iOS Simulator — and sees everything on screen, including what Flutter cannot: permission dialogs, system alerts, sheets and pickers, notifications, browser sign-in, native screens, platform views and WebView content.

Prefer the Flutter lane for in-app widgets; switch to the native lane when the target is not in the Flutter tree.

## Setup

### Android

`native_connect` with `platform: android` uses **UIAutomator2** over adb. Marionette does **not** install adb for you — it must already be on your `PATH` (Android SDK Platform Tools; usually present if you run Flutter on Android):

```bash
which adb          # should print a path
adb devices        # device/emulator must show state "device"
```

You also need a connected Android device or emulator. Optionally pass `serial` to `native_connect` when multiple devices are attached.

On first connect, Marionette **downloads and caches** the UIAutomator2 server APKs (Appium v10.3.2). To use local APKs instead:

```bash
export MARIONETTE_UIA2_SERVER_APK=/path/to/appium-uiautomator2-server.apk
export MARIONETTE_UIA2_TEST_APK=/path/to/appium-uiautomator2-server-debug-androidTest.apk
```

Downloaded APKs are verified against pinned SHA-256 checksums, and an APK is only installed when the copy on the device differs, so reconnecting is fast.

Marionette forwards a local port to UIAutomator2: by default the first free port from 8200 (an existing forward for the same device is reused). To pin it:

```bash
export MARIONETTE_UIA2_PORT=8200
```

If the device-side server dies during a session, call `native_connect` again.

### iOS (Simulator)

`native_connect` with `platform: ios` uses **WebDriverAgent (WDA)** on an **iOS Simulator** (real devices are not supported yet). Unlike Android, Marionette does **not** download or build WDA for you — you need a **one-time build**, then Marionette can launch and reuse it.

**Host & tools**

- **macOS only** — WDA bootstrap uses `xcrun simctl` and `xcodebuild` (from Xcode).
- A **booted iOS Simulator** (`open -a Simulator`, or `xcrun simctl boot "iPhone 16"`). Optionally pass `udid` to `native_connect` when several simulators are booted.

**One-time WebDriverAgent build**

```bash
git clone https://github.com/appium/WebDriverAgent.git
cd WebDriverAgent
xcodebuild build-for-testing \
  -project WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination 'platform=iOS Simulator,id=<UDID>'
```

Get `<UDID>` from `xcrun simctl list devices`. Build for the simulator runtime you plan to use — rebuild if you switch to an incompatible OS/arch.

**Point Marionette at the build** (pick one):

```bash
# Preferred: .xctestrun from DerivedData/Build/Products
export MARIONETTE_WDA_XCTESTRUN=/path/to/WebDriverAgentRunner_*.xctestrun

# Or the runner .app / Products directory
export MARIONETTE_WDA_BUNDLE=/path/to/WebDriverAgentRunner-Runner.app
export MARIONETTE_WDA_PATH=/path/to/DerivedData/Build/Products
```

Or copy the build output into `~/.cache/marionette_mcp/wda/` — Marionette scans that directory automatically (no env vars needed once artifacts are there). On connect it runs `xcodebuild test-without-building` against the `.xctestrun`, or falls back to `simctl install` + `simctl launch` for a `.app` bundle.

### MCP and CLI

- **MCP:** `native_connect` with `platform` (`android` / `ios`) and optionally `serial` / `udid`. The server process holds the device-side server until `native_disconnect` or exit.
- **CLI:** `marionette native-connect --platform android|ios` starts the device-side server **detached** from the CLI, so every later `marionette native-*` command attaches to it and reuses the WebDriver session; `native-disconnect` stops it. `--native-device <name>` drives several devices at once ([CLI guide](./cli.md#native-lane-system-ui)).

Use one client per Android device at a time: UIAutomator2 has a single session, so an MCP server and a CLI session on the same device take it from each other: the CLI opens a new session for its next command, the MCP server needs `native_connect` again.

### Screenshots and session reports

`native_take_screenshot` returns an inline PNG. With `inline: false` it saves the screenshot into the session directory instead (`screenshots/`), like `take_screenshots`. The session is opened by the Flutter lane's `connect` when the app enables session reports, and `native_*` calls are logged to its `steps.md` too. In the CLI, a `native-*` command logs its step only when `--session` or `--session-dir` is given, since it has no Flutter connection to ask whether reports are enabled.

## Working with it

- **Find:** `native_get_elements` lists what is on screen — type, text, id, `bounds` and, when informative, state: `value` (a field's typed content; its `text` stays the label), `enabled`, `focused`, `checked`, `selected`, `scrollable`. Only on-screen elements are listed.
- **Select:** element tools take `text`, `textContains`, `id`, `type`, `index`. When several elements match and clickable ones do not narrow it to one, the tool fails and lists the candidates instead of guessing.
- **Coordinates** (`x`/`y`, `bounds`, swipe points) are screenshot pixels on every platform. Never reuse Flutter coordinates.
- **Wait** with `native_wait_for` (visible / gone, hard `timeoutMs`) rather than fixed delays.
- **Scroll** with `native_scroll`: until a target is visible, inside a container (`within`), stopping at the end of the list. `native_swipe` is a raw gesture that does not wait for the content to settle.
- **Type** with `native_enter_text` (appends; `clear` empties first; without a selector it types into the focused field). Hide the keyboard with `native_hide_keyboard`; keys with `native_press_key`.
- **Permissions:** answer the system dialog with `native_wait_for` + `native_tap`. It shows only while the permission is undecided; to see it again, reset the permission outside Marionette (`adb shell pm revoke <package> <permission>`, `xcrun simctl privacy <udid> reset all <bundle id>`).
- **Notifications:** `native_notifications` opens / closes the shade (Android) or the Notification Center (iOS); read them with `native_get_elements` and open one with `native_tap` (iOS Notification Center: a group expands on the first tap; if a tap only shows an "Open" button, tap "Open").
- **Screenshots** of system UI with `native_take_screenshot` (whole screen); Flutter's `take_screenshots` shows only Flutter.
- **When the app is covered**, `get_interactive_elements` warns that it is not in front — except for an alert or sheet the app itself shows on iOS.

The MCP server sends these rules to the agent as its instructions; the CLI prints them with `marionette help-ai`.

## What each lane sees

Verified on an Android emulator (API 28, 29, 35) and the iOS Simulator (18.6, 26.4).

| UI | Flutter lane | Native lane | Notes |
| --- | --- | --- | --- |
| Native controls in a platform view | — | ✓ read, tap, type | On iOS `take_screenshots` does not show them |
| Camera preview, map, video surface | — | — (only the surrounding controls) | |
| WebView content | — | ✓ fields, buttons, links, `select` | Android: HTML ids as `id`; iOS: off-screen parts are not listed |
| Permission dialogs | — | ✓ | |
| File / photo pickers, camera, share sheet | — | ✓ | Reads next to iOS pickers take 2–3 s |
| Software keyboard | — | iOS: keys are elements; Android: not exposed | Type with `native_enter_text` |
| Native alerts (`AlertDialog`, `UIAlertController`, ATT) | — | ✓ | |
| Native screens (Activity / view controller) | — | ✓ | |
| Notifications | — | ✓ in the shade / Notification Center | iOS: a group expands on the first tap, a tap may only show "Open"; Android heads-up banners only on screenshots |
| Toasts (Android) | — | API 28–29: read-only element; API 35: screenshot only | Reads wait while a toast is shown |
| Biometric prompt | — | ✓ read | Answering it needs simulated biometrics, which the tools do not offer |
| Browser sign-in (Custom Tab, `ASWebAuthenticationSession`) | — | ✓ consent alert, form, redirect | |
| Autofill | — | iOS: QuickType bar; Android emulator: none | |

## Platform notes

- **Android:** with a hardware keyboard Gboard shows a floating toolbar that `native_hide_keyboard` will not "hide" with Back; reads on continuously animating screens are kept short by a 500 ms idle wait.
- **iOS (Simulator):** a notification banner shows only while the app is in the background; keyboards without a Done key cannot be hidden by the tool; a focused Flutter field adds its hint to its label.
- **Both:** an element covered by another one (e.g. under a toolbar) still counts as visible — scroll a little more before tapping near an edge; after a lost device-side session call `native_connect` again.

Problems and fixes: [Troubleshooting → Native lane](./troubleshooting.md#native-lane).
