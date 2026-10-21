# Troubleshooting

## Common gotchas

Most "Marionette doesn't work" reports trace back to missing configuration. Match your symptom:

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Custom buttons / controls don't show up in `get_interactive_elements` | Custom widget type isn't recognized as interactive | Add it to [`isInteractiveWidget`](./configuration.md#isinteractivewidget) |
| `tap(text:)` / `scroll_to(text:)` can't find a custom field or label | Text isn't extracted from the widget | Implement [`extractText`](./configuration.md#extracttext) |
| Custom-painted text, badges, charts are invisible to the agent | Text never reaches a `Text` widget | Annotate with [`Semantics`](./semantics.md) |
| `get_logs` says no collector is configured | No `LogCollector` wired up | See [Log Collection](./logging.md) |
| Widget coverage looks low / agent can't reach nested content | Over-aggressive `shouldStopTraversal` | **Leave it `null`** — never filter scroll containers ([why](./configuration.md#shouldstoptraversal)) |
| Binding assertion error on startup, often in tests | Two `WidgetsBinding`s initialized | See the [single-binding rule](./flutter-setup.md#single-binding-rule) |
| `connect` fails with a version mismatch | `marionette_mcp`/`marionette_cli` and `marionette_flutter` are different versions | Align both packages to the same version |

## Quick fixes

- **"Not connected to any app"** — ensure the agent called `connect` with a valid VM Service URI before any other tool.
- **Finding the URI** — run your app in debug mode (`flutter run`) and look for a line like `... is available at: http://127.0.0.1:9101?uri=ws://127.0.0.1:9101/ws`. Use the `ws://...` part.
- **Release mode** — Marionette only works in **debug and profile** mode because it relies on the VM Service. It will not work in release builds.
- **Elements not found** — make sure the widget is actually visible on screen. If it's a custom widget, confirm it's covered by your [`MarionetteConfiguration`](./configuration.md).

## Native lane

Background: [Native lane](./native-lane.md).

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `native_connect` (Android): device not online / adb not found | No device, unauthorized device, adb missing | Start an emulator or accept the USB-debugging prompt; install platform-tools |
| `native_connect` (Android): "device … is locked" (`deviceLocked`) | The device was restarted and has a PIN / pattern / password: its storage stays encrypted until the first unlock | Unlock the screen (emulator: wake it, swipe up, `adb shell input text <PIN>`, Enter), then connect again |
| `native_connect` (Android): APK download fails | No network on the first connect | Connect once with network access, or point `MARIONETTE_UIA2_SERVER_APK` / `MARIONETTE_UIA2_TEST_APK` at local APKs |
| `native_connect` (iOS): no prebuilt WebDriverAgent | WDA was never built | Build it once ([README](../README.md#native-lane-requirements-ios)) or set `MARIONETTE_WDA_XCTESTRUN` |
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

## Assumptions & limitations

- **Prefer pasting the VM Service URI manually.** Some tooling can discover or infer the endpoint, but the most reliable workflow is to copy the `ws://.../ws` URI from your `flutter run` output (or a DevTools link) and paste it to the agent when calling `connect`.

- **The agent may not know your app.** Marionette can "see" the widget tree and interact with UI, but it doesn't automatically understand your product's flows, naming conventions, or edge cases. For reliable navigation and assertions, give the agent context in the prompt: what screen to reach, expected labels/keys, preconditions, and the goal of the interaction.

- **"Your mileage may vary" interactions.** Some actions are best-effort simulations of user behavior (gestures, focus, text entry, scrolling). Depending on platform, custom widgets, overlays, or app-specific gesture handling, results may vary. If a flow is flaky, consider exposing clearer widget keys, simplifying hit targets, or adding custom [`MarionetteConfiguration`](./configuration.md) hooks for your design system. If something consistently misbehaves, a small repro in an [issue](https://github.com/leancodepl/marionette_mcp/issues) helps us improve it.
