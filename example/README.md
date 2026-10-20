# Marionette MCP Example

A multi-page Flutter app demonstrating **`call_custom_extension`** with Marionette MCP.

## App Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Home | Welcome screen |
| `/profile` | Profile | User profile |
| `/testing` | Testing | Native-lane test cases hub |
| `/testing/webview` | WebView | Local HTML form (default, no network) or the marionette_mcp website (§2) |
| `/testing/platform-views` | Platform views | Native controls, camera, Google Maps (needs an API key), video (§1) |
| `/testing/permission-dialogs` | Permission dialogs | OS permission prompts (§3) |
| `/testing/pickers-and-sheets` | Pickers & sheets | File, photo, camera, share (§4) |
| `/testing/keyboard` | Keyboard / IME | Numeric, return, done keyboards (§8) |
| `/testing/gestures` | Gestures & inspection | Element state, gestures, waiting, scrolling in containers |
| `/testing/device` | Device & permissions | Every permission group, orientation, deep link query |
| `/testing/native-dialogs` | Native dialogs | Platform alert (Android `AlertDialog`, iOS `UIAlertController`) and the iOS tracking (ATT) prompt (§11) |
| `/testing/native-screen` | Native screen | A native screen with a text field; its value returns to Flutter (§10) |
| `/testing/notifications` | Notifications | Local notification after 3 s, opening the app from it, Android toast (§9) |
| `/testing/auth` | Auth | Biometric prompt (`local_auth`) and an autofill username / password form (§5) |
| `/testing/oauth` | OAuth | Browser sign-in (Custom Tab / `ASWebAuthenticationSession`) against an in-app local server (§7) |
| `/settings` | Settings | Gesture and UI demos |

## Custom VM Service Extensions

### `appNavigation.getPageInfo`

Returns the current page and all available pages.

```
call_custom_extension(
  extension: "appNavigation.getPageInfo"
)
→ {"status":"Success","currentPage":"home","currentPath":"/","availablePages":["home","profile","testing","permission_dialogs",...]}
```

### `appNavigation.goToPage`

Navigate directly to any page by name — even nested pages that require multiple UI taps.

```
call_custom_extension(
  extension: "appNavigation.goToPage",
  args: { page: "permission_dialogs" }
)
→ {"status":"Success","page":"permission_dialogs","path":"/testing/permission-dialogs"}
```

## Why `call_custom_extension` Matters

The Permission dialogs page is nested under Testing. Via the UI, reaching it requires:

1. Tap the Testing tab
2. Tap the Permission dialogs list tile

With `call_custom_extension`, an AI agent can jump there in a single call — no multi-step UI interaction needed.

## Deep links

The app handles the `marionette-example://` scheme (Android intent filter, iOS `CFBundleURLTypes`); the path after the host is the route:

```
native_open_url(url: "marionette-example://app/testing/device?from=link")
```

opens Device & permissions, which shows the query (`from=link`). On iOS the system first asks "Open in …?" — confirm with `native_tap text="Open"`.

## Permissions on iOS

The app declares camera, photos, microphone, location (when in use), contacts, calendar, Face ID and tracking (ATT). The project builds plugins with Swift Package Manager, where `permission_handler_apple` enables a permission only when its usage-description key is in `ios/Runner/Info.plist` (the `PERMISSION_*` macros in `ios/Podfile` apply to CocoaPods builds only). After adding or removing such a key, delete `~/Library/Developer/Xcode/DerivedData/Runner-*` before building — otherwise the permission stays "denied" and no dialog appears.

## Native screens, notifications and sign-in

- **Native dialogs / native screen** use the `marionette-demo/native` method channel (`MainActivity.kt`, `NativeFormActivity.kt`, `AppDelegate.swift`). Native ids: `native_form_name`, `native_form_back` (Android: `com.example.counter:id/…`; iOS: accessibility identifiers).
- **Notifications:** send the app to the background (`native_app action=background`) within 3 s to see the banner. iOS schedules the notification with the system (a suspended app cannot post it); Android posts it from a timer. On iOS a notification in the Notification Center opens with a swipe right, not a tap; on Android heads-up banners are visible only on screenshots, toasts too on recent versions (API 28 lists them as read-only elements). After a cold start from a notification the app opens on Home — open the Notifications screen to see the payload. On Android, `native_app action=terminate` removes the notification; let the system kill the app instead (`adb shell am kill com.example.counter` while it is in the background).
- **Biometrics:** `native_biometrics` answers the prompt. iOS: `enroll` first. Android emulator: set a screen lock (`adb shell locksettings set-pin 1111`) and enroll a fingerprint in Settings once, answering its steps with `native_biometrics action=match`.
- **OAuth:** the app serves the sign-in form itself on `127.0.0.1` (no network) and redirects to `marionette-auth://callback`. iOS first asks "“counter” Wants to Use “127.0.0.1” to Sign In" (SpringBoard alert: Continue / Cancel).

## Google Maps key

The map screen needs a Maps API key: `google.maps.api.key=…` in `android/local.properties` and `GOOGLE_MAPS_API_KEY` in `ios/Runner/Info.plist` (do not commit a real key). Without one the map stays blank, shows no marker and reports no camera changes.

## Running

```bash
cd example
flutter pub get
flutter run -d macos   # or: flutter run -d chrome
```

Connect via Marionette MCP, then use `call_custom_extension` to navigate.
