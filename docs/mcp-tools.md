# MCP Tools

This page moved to the Marionette website:

- [Drive: every tool](https://marionette.leancode.co/docs/drive#tools)
- [Start: give your agent the tools](https://marionette.leancode.co/docs#bridge)

The native lane tools are documented here until they move to the website.

## Native lane

Tools for system / native UI outside the Flutter widget tree (permission dialogs, OS sheets and pickers, embedded WebViews, native views, notifications). Setup, workflow and what each lane sees: [Native lane](./native-lane.md). All native tools use the `native_` prefix. Call `native_connect` first.

| Tool | Description |
| --- | --- |
| `native_connect` | Start a native automation session (UIAutomator2 on Android, WebDriverAgent on iOS). Requires `platform`: `android` or `ios`. If the device-side server or session is lost later, call it again. |
| `native_disconnect` | Stop the native session and release device-side processes. |
| `native_get_elements` | Return the native UI hierarchy as JSON (`elements`, optional `foregroundApp`). `bounds` are in screenshot pixels on every platform. State is included when it carries information: `value` (a text field's content — its `text` stays the label), `enabled: false`, `focused: true` (Android), `checked`, `selected: true`, `scrollable: true`. Optional filters: `text`, `textContains`, `id`, `type`, `clickableOnly`; `includeForegroundApp: false` skips the foreground app. Only on-screen elements are listed; on iOS partly visible ones are clipped to the screen, as on Android. |
| `native_wait_for` | Wait until an element matching a selector is visible (`state: visible`, default; returns it) or `gone`. `timeoutMs` default 10000 (max 60000), `intervalMs` default 500. A timeout names the foreground app. |
| `native_tap` | Tap an element chosen by a selector (`text`, `textContains`, `id`, `type`, optional `index`) or at `x`/`y` in screenshot pixels. An ambiguous selector fails and lists the candidates. |
| `native_scroll` | Swipe in a `direction` from screen center (default), inside a container (`within`: a selector) or from `startX`/`startY`; optionally scroll until an element matching `text` / `textContains` / `id` / `type` is visible, up to `maxSwipes` (default 10). Searching uses slow drags so the list does not fling past the target, waits for the content to settle, and stops early when the content no longer moves (end of the list). |
| `native_swipe` | Swipe one finger from `startX`/`startY` to `endX`/`endY` (screenshot pixels) over `durationMs` (default 300) — drags, sliders, edge gestures (iOS back: start at `x=1`). |
| `native_enter_text` | Type `text` into a native field chosen by a selector (`label`, `textContains`, `id`, `type`, optional `index`), or — without a selector — into the field that has keyboard focus. Text is appended; `clear: true` empties the field first; a field that changed before anything was typed is found again once. `label` also matches the first line of a field's label. |
| `native_press_key` | Press a system / hardware key: `back`, `home`, `enter`, `backspace`, `tab`, `recents`, `volume_up`, `volume_down`. `back`, `recents` and `tab` are Android-only; the iOS Simulator has only `home` of the hardware buttons. |
| `native_hide_keyboard` | Hide the software keyboard if it is shown and report whether it was. Android presses Back only while the keyboard is shown; iOS uses the keyboard's Done / dismiss key and fails with a hint when there is none; Android fails with a hint when only Gboard's floating toolbar is shown (hardware keyboard attached), because Back would close the screen. |
| `native_take_screenshot` | Returns a base64 inline PNG of the full device screen via the native session (system UI, WebViews). When `MARIONETTE_SCREENSHOTS_DIR` is set, also saves the PNG to that directory and includes the absolute path alongside the inline image. |
| `native_notifications` | `open` / `close` the notification shade (Android) or Notification Center (iOS, by swipe). Open a notification with `native_tap`. In the iOS Notification Center the first tap on a group of one app's notifications expands it, and a tap on a notification may only slide it aside and show an "Open" button — wait for it (`native_wait_for` `text: "Open"`) and tap it; a collapsed "N Notifications" button must be tapped first. Android heads-up banners are not in the tree — read them with `native_take_screenshot`. Toasts: on older Android (seen on API 28) listed read-only by `native_get_elements` / `native_wait_for` (`android.widget.Toast`, no bounds, cannot be tapped); on recent Android (API 35) not listed, and a tree read waits until the toast is gone. |
