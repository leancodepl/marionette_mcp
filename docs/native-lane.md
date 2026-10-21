# Native lane

Marionette drives a Flutter app through two lanes:

- the **Flutter lane** (`connect`, `tap`, `get_interactive_elements`, …) talks to the app over the VM service and sees the widget tree;
- the **native lane** (`native_*` tools, `marionette native-*` commands) talks to the platform's UI automation server — **UIAutomator2** on Android, **WebDriverAgent** on the iOS Simulator — and sees everything on screen, including what Flutter cannot: permission dialogs, system alerts, sheets and pickers, notifications, browser sign-in, native screens, platform views and WebView content.

Prefer the Flutter lane for in-app widgets; switch to the native lane when the target is not in the Flutter tree. Why the tools behave the way they do is recorded in [Native lane design decisions](./native-lane-decisions.md) (D1–D22), referenced below as **Dn**.

## Setup

### Android

- `adb` on `PATH` (Android SDK platform-tools) and an emulator or a phone with USB debugging.
- Nothing else: on the first `native_connect` Marionette downloads the pinned UIAutomator2 APKs (checked against their SHA-256), installs them only when they changed, and forwards a free local port (`MARIONETTE_UIA2_PORT` to fix one) — [D10](./native-lane-decisions.md#d10).

### iOS (Simulator)

- macOS with Xcode and a booted simulator. Real iPhones are not supported yet.
- A one-time WebDriverAgent build — see the [README](../README.md#native-lane-requirements-ios); Marionette finds it in `~/.cache/marionette_mcp/wda/` or through `MARIONETTE_WDA_XCTESTRUN`. A WebDriverAgent already running for the simulator is reused ([D10](./native-lane-decisions.md#d10)).

### MCP and CLI

- **MCP:** `native_connect` with `platform` (`android` / `ios`) and optionally `serial` / `udid`. The server process holds the device-side server until `native_disconnect` or exit.
- **CLI:** `marionette native-connect --platform android|ios` starts the device-side server **detached** from the CLI, so every later `marionette native-*` command attaches to it and reuses the WebDriver session; `native-disconnect` stops it. `--native-session <name>` drives several devices at once ([D4](./native-lane-decisions.md#d4), [CLI guide](./cli.md#native-lane-system-ui)).

Use one client per Android device at a time: UIAutomator2 has a single session, so an MCP server and a CLI session on the same device take it from each other: the CLI opens a new session for its next command, the MCP server needs `native_connect` again.

## Working with it

- **Find:** `native_get_elements` lists what is on screen — type, text, id, `bounds` and, when informative, state: `value` (a field's typed content; its `text` stays the label), `enabled`, `focused`, `checked`, `selected`, `scrollable` ([D15](./native-lane-decisions.md#d15)). Only on-screen elements are listed ([D16](./native-lane-decisions.md#d16)).
- **Select:** element tools take `text`, `textContains`, `id`, `type`, `index`. When several elements match and clickable ones do not narrow it to one, the tool fails and lists the candidates instead of guessing ([D1](./native-lane-decisions.md#d1)).
- **Coordinates** (`x`/`y`, `bounds`, swipe points) are screenshot pixels on every platform ([D2](./native-lane-decisions.md#d2)). Never reuse Flutter coordinates.
- **Wait** with `native_wait_for` (visible / gone, hard `timeoutMs`) rather than fixed delays ([D16](./native-lane-decisions.md#d16)).
- **Scroll** with `native_scroll`: until a target is visible, inside a container (`within`), stopping at the end of the list ([D16](./native-lane-decisions.md#d16)). `native_swipe` is a raw gesture that does not wait for the content to settle.
- **Type** with `native_enter_text` (appends; `clear` empties first; without a selector it types into the focused field). Hide the keyboard with `native_hide_keyboard`; keys with `native_press_key` ([D14](./native-lane-decisions.md#d14)).
- **Permissions:** answer the system dialog with `native_wait_for` + `native_tap`. It shows only while the permission is undecided; to see it again, reset the permission outside Marionette (`adb shell pm revoke <package> <permission>`, `xcrun simctl privacy <udid> reset all <bundle id>`).
- **Notifications:** `native_notifications` opens / closes the shade (Android) or the Notification Center (iOS); read them with `native_get_elements` and open one with `native_tap` (iOS Notification Center: a swipe right, [D21](./native-lane-decisions.md#d21)).
- **Screenshots** of system UI with `native_take_screenshot` (whole screen); Flutter's `take_screenshots` shows only Flutter.
- **When the app is covered**, `get_interactive_elements` warns that it is not in front — except for an alert or sheet the app itself shows on iOS ([D22](./native-lane-decisions.md#d22)).

The MCP server sends these rules to the agent as its instructions; the CLI prints them with `marionette help-ai`.

## What each lane sees

Verified on an Android emulator (API 28, 29, 35) and the iOS Simulator (18.6, 26.4).

| UI | Flutter lane | Native lane | Notes |
| --- | --- | --- | --- |
| Native controls in a platform view | — | ✓ read, tap, type | On iOS `take_screenshots` does not show them |
| Camera preview, map, video surface | — | — (only the surrounding controls) | |
| WebView content | — | ✓ fields, buttons, links, `select` | Android: HTML ids as `id`; iOS: off-screen parts are not listed |
| Permission dialogs | — | ✓ | |
| File / photo pickers, camera, share sheet | — | ✓ | Reads next to iOS pickers take 2–3 s ([D16](./native-lane-decisions.md#d16)) |
| Software keyboard | — | iOS: keys are elements; Android: not exposed | Type with `native_enter_text` |
| Native alerts (`AlertDialog`, `UIAlertController`, ATT) | — | ✓ | |
| Native screens (Activity / view controller) | — | ✓ | |
| Notifications | — | ✓ in the shade / Notification Center | iOS: open one with a swipe right ([D21](./native-lane-decisions.md#d21)); Android heads-up banners only on screenshots |
| Toasts (Android) | — | API 28–29: read-only element; API 35: screenshot only | Reads wait while a toast is shown ([D19](./native-lane-decisions.md#d19)) |
| Biometric prompt | — | ✓ read | Answering it needs simulated biometrics, which the tools do not offer |
| Browser sign-in (Custom Tab, `ASWebAuthenticationSession`) | — | ✓ consent alert, form, redirect | |
| Autofill | — | iOS: QuickType bar; Android emulator: none | |

## Platform notes

- **Android:** with a hardware keyboard Gboard shows a floating toolbar that `native_hide_keyboard` will not "hide" with Back ([D14](./native-lane-decisions.md#d14)); reads on continuously animating screens are kept short by a 500 ms idle wait ([D18](./native-lane-decisions.md#d18)).
- **iOS (Simulator):** a notification banner shows only while the app is in the background ([D21](./native-lane-decisions.md#d21)); keyboards without a Done key cannot be hidden by the tool ([D14](./native-lane-decisions.md#d14)); a focused Flutter field adds its hint to its label ([D15](./native-lane-decisions.md#d15)).
- **Both:** an element covered by another one (e.g. under a toolbar) still counts as visible — scroll a little more before tapping near an edge; after a lost device-side session call `native_connect` again.

## Testing the native lane

Device tests (tag `device`) drive the example app through the real MCP server and CLI. They are skipped by a plain `dart test`:

```sh
cd packages/marionette_mcp && dart test -P device       # Android
MARIONETTE_E2E_PLATFORM=ios dart test -P device         # iOS Simulator
cd packages/marionette_cli && dart test -P device
```

The example app must be installed; set `MARIONETTE_E2E_VM_SERVICE_URI` (from `flutter run`) to include the scenario that uses both lanes. On failure a screenshot, the native tree and the server log are written to `MARIONETTE_E2E_ARTIFACTS`.

Problems and fixes: [Troubleshooting → Native lane](./troubleshooting.md#native-lane).
