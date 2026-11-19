# The native lane

It reaches what the platform draws: permission dialogs, system alerts (also a
plugin's), photo and file pickers, share sheets, the camera UI, WebView
content, platform views, native screens, notifications. Device setup (adb,
WebDriverAgent, hosts) is in `marionette-flutter-setup`.

`get_interactive_elements` warns "the app is not in front" when system UI
covers the app; trust it. An alert or sheet the app itself shows on iOS gives
no warning: when a Flutter action has no visible effect, check
`native_get_elements`. The warning lags a moment: after system UI opens or
closes, `native_wait_for` the next screen before you trust the Flutter list.

## Connect

- `native_connect` with `platform: android | ios`, plus `serial` / `udid` with
  several devices attached; it is independent of `connect`, and a run usually
  needs both. Call it before the flow opens system UI: starting WebDriverAgent
  can dismiss an alert on screen. On failure, follow the error's hint. Nothing
  reconnects by itself: when a native call says the device-side server or
  session is gone, call `native_connect` again.
- One client per device: an MCP server and a CLI session on the same device
  take the single device-side session from each other. One iOS Simulator at a
  time. Call `native_disconnect` when you're done.

## Work with it

- **Look first.** `native_get_elements` lists type, text, id, bounds, state
  (`value` is a field's typed content; its `text` stays the label) and
  `foregroundApp`, whose UI is in front. `native_take_screenshot` shows the
  whole screen; `take_screenshots` only Flutter.
- **Read before you look.** The tree costs a few hundred tokens, a screenshot
  about 1.5k. Take one only for what the tree lacks (heads-up banners, a camera
  preview, toasts: the tree cannot show a toast on recent Android, where a read
  fails while one shows, or on iOS), with `inline: false` for evidence.
- **Selectors:** `text`, `textContains`, `id` (on Android the full resource id,
  `package:id/name`), `type`, `index`; `native_enter_text` picks a field by
  `label`. An ambiguous selector fails and lists the candidates: add `index` or
  a more specific `type` / `id`, don't guess. A disabled element
  (`enabled: false`) is refused. On iOS the app's elements stay listed under a
  sheet or alert, not all disabled (the app's own alerts disable none): when an
  `XCUIElementTypeAlert` or a sheet is listed, act on it first.
- **Coordinates** (`x`/`y`, `bounds`, swipe points) are screen pixels on every
  platform; never reuse Flutter coordinates here or the other way round.
  `native_take_screenshot` fits the image in 2000×2000; multiply a point read
  off a shrunk image by the factor the result gives.
- **Wait, don't sleep.** `native_wait_for` (`visible` or `gone`, hard
  `timeoutMs`) an element of the dialog or next screen, not a package name.
- **Scroll** with `native_scroll`: with a target it stops once the target is
  visible or the list ends; `within` scrolls a nested list or a picker wheel.
  `native_swipe` is raw and doesn't wait for the content to settle.
- **Keyboard.** `native_press_key` for `back` (Android only), `home`, `enter`
  and others; `native_hide_keyboard` when it is in the way. `native_enter_text`
  without a selector types into the focused field, also a Flutter field Android
  doesn't list. On iOS, after the keyboard scrolls a WebView, WebKit can report
  elements shifted until the WebView is opened again: if a tap misses, compare
  with `native_take_screenshot` and tap by coordinates.
- **Permissions.** `native_wait_for` + `native_tap`. A dialog shows only while
  the permission is undecided. To see it again, reset it outside Marionette
  (`adb shell pm revoke <package> <permission>`,
  `xcrun simctl privacy <udid> reset all <bundle id>`), then `connect` again:
  the reset ends the Flutter connection.
- **Notifications.** `native_notifications` opens / closes the shade (Android)
  or the Notification Center (iOS); read it with `native_get_elements`, open
  one with `native_tap`. On iOS the first tap on an app's group (or a collapsed
  "N Notifications" button) expands it, and a notification opens with a swipe
  right (`native_swipe`) across its full width at its vertical center, not a
  tap. Background the app (`native_press_key` `home`) and wait until the banner
  is gone before opening the Notification Center.

## Reports and the CLI

Native calls go to the same `steps.md` once `connect` has opened a session, so
`Tested:` covers both lanes; `native_take_screenshot(inline: false)` saves into
`screenshots/`. A CLI `native-*` command logs its step only with `--session`,
`--session-dir` or `MARIONETTE_SESSION_DIR`. `native-connect`
(`--platform android|ios`) starts the device-side server detached; later
commands (`native-tap --text Allow`) reuse it, `native-disconnect` stops it.
`--native-device <name>` (before the command) names a connection to drive
several devices; it is unrelated to `--session`.
