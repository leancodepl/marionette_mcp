# Marionette MCP Example

A multi-page Flutter app demonstrating **`call_custom_extension`** with Marionette MCP.

## App Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Home | Welcome screen |
| `/profile` | Profile | User profile |
| `/testing` | Testing | Native-lane test cases hub |
| `/testing/webview` | WebView | Local HTML form (default, no network) or the marionette_mcp website |
| `/testing/platform-views` | Platform views | Native controls, camera, Google Maps (needs an API key), video |
| `/testing/permission-dialogs` | Permission dialogs | OS permission prompts |
| `/testing/pickers-and-sheets` | Pickers & sheets | File, photo, camera, share |
| `/testing/keyboard` | Keyboard / IME | Numeric, return, done keyboards |
| `/testing/native-dialogs` | Native dialogs | Platform alert (Android `AlertDialog`, iOS `UIAlertController`) and the iOS tracking (ATT) prompt |
| `/testing/native-screen` | Native screen | A native screen with a text field; its value returns to Flutter |
| `/testing/notifications` | Notifications | Local notification after 3 s, opening the app from it, Android toast |
| `/testing/oauth` | OAuth | Browser sign-in (Custom Tab / `ASWebAuthenticationSession`) against an in-app local server |
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
adb shell am start -a android.intent.action.VIEW -d 'marionette-example://app/testing/keyboard'
xcrun simctl openurl booted marionette-example://app/testing/keyboard
```

open the Keyboard screen; the E2E tests navigate this way. On iOS the system may first ask "Open in …?" — confirm with `native_tap text="Open"`.

## Permissions on iOS

The app declares camera, photos and tracking (ATT). The project builds plugins with Swift Package Manager, where `permission_handler_apple` enables a permission only when its usage-description key is in `ios/Runner/Info.plist` (the `PERMISSION_*` macros in `ios/Podfile` apply to CocoaPods builds only). After adding or removing such a key, delete `~/Library/Developer/Xcode/DerivedData/Runner-*` before building — otherwise the permission stays "denied" and no dialog appears.

## Native screens, notifications and sign-in

- **Native dialogs / native screen** use the `marionette-demo/native` method channel (`MainActivity.kt`, `NativeFormActivity.kt`, `AppDelegate.swift`). Native ids: `native_form_name`, `native_form_back` (Android: `com.example.counter:id/…`; iOS: accessibility identifiers).
- **Notifications:** send the app to the background (`native_press_key key=home`) within 3 s to see the banner. iOS schedules the notification with the system (a suspended app cannot post it); Android posts it from a timer. On iOS a notification in the Notification Center opens with a swipe right, not a tap; on Android heads-up banners are visible only on screenshots, toasts too on recent versions (API 28 lists them as read-only elements). After a cold start from a notification the app opens on Home — open the Notifications screen to see the payload. On Android, force-stopping the app removes the notification; let the system kill the app instead (`adb shell am kill com.example.counter` while it is in the background).
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
