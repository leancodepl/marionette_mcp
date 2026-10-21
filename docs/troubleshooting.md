# Troubleshooting

This page moved to the Marionette website:

- [Configure: start from the symptom](https://marionette.leancode.co/docs/configure#symptoms)
- [Start: FAQ](https://marionette.leancode.co/docs#faq)

## Native lane

Background: [Native lane](./native-lane.md).

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `native_connect` (Android): device not online / adb not found | No device, unauthorized device, adb missing | Start an emulator or accept the USB-debugging prompt; install platform-tools |
| `native_connect` (Android): "device … is locked" (`deviceLocked`) | The device was restarted and has a PIN / pattern / password: its storage stays encrypted until the first unlock | Unlock the screen (emulator: wake it, swipe up, `adb shell input text <PIN>`, Enter), then connect again |
| `native_connect` (Android): APK download fails | No network on the first connect | Connect once with network access, or point `MARIONETTE_UIA2_SERVER_APK` / `MARIONETTE_UIA2_TEST_APK` at local APKs |
| `native_connect` (iOS): no prebuilt WebDriverAgent | WDA was never built | Build it once ([Native lane → iOS](./native-lane.md#ios-simulator)) or set `MARIONETTE_WDA_XCTESTRUN` |
| `native_connect` (iOS): port 8100 conflict | Another program, or WDA of another simulator, listens on 8100 | `lsof -nP -iTCP:8100 -sTCP:LISTEN` and stop it |
| "The native session was lost …" | The device-side server died or another client took the session | Call `native_connect` again. Use one client per Android device |
| A Flutter tap does nothing while a dialog is open | System UI covers the app; the Flutter tree still lists the widgets below | `get_interactive_elements` warns when it can; use `native_get_elements` / `native_tap` |
| `native_tap` fails: several elements match | Ambiguous selector | Add `index` or a more specific `type` / `id` |
| `native_wait_for` never sees an element that is on screen | It appeared below the bottom edge (off-screen elements are not listed) | Scroll it into view first |
| `native_hide_keyboard` refuses on an Android emulator | Gboard's floating toolbar (hardware keyboard attached) | Unfocus the field in the app, or start the emulator with `hw.keyboard=no` |
| Reads take 2–3 s next to iOS pickers | WebDriverAgent snapshots the picker of another process | Expected; prefer `native_wait_for` over repeated reads |
| `native_tap`: "is disabled, so it was not touched" | The element has `enabled: false` — on iOS the app's elements stay listed, disabled, while a system sheet or picker covers them | Act on the sheet or picker in front, or close it (e.g. its Cancel button), then retry; `native_get_elements` shows what is in front |
| A checkbox in a WebView (Android) has no `checked` state | Android WebView reports HTML checkboxes as not checkable, whatever their state | Read the state from the page (a label or result it shows) or take a screenshot; on iOS the checkbox is a `Switch` with `checked` |
| iOS notification in the Notification Center does not open on tap | The first tap expands a group of the app's notifications; a tap on a notification may only slide it aside | Tap the notification in the expanded group; if an "Open" button appears, wait for it (`native_wait_for`) and tap it |
| iOS: the app closes on its own; tools still succeed but `foregroundApp` is SpringBoard or Spotlight | A crash inside XCTest in the app (`EXC_BAD_ACCESS` in `XCTAutomationSession`, see `~/Library/Logs/DiagnosticReports/Runner-*.ips`), seen when WebDriverAgent is stopped and started again many times — e.g. a new MCP server process per call | Keep one session: a long-lived MCP server, or a detached WDA (`marionette native-connect --platform ios`) that later processes reuse; start the app again (`xcrun simctl launch booted <bundle id>`) |
| iOS: notifications never show | Alerts disabled for the app after earlier installs | Reinstall the app or enable notifications in Settings |

