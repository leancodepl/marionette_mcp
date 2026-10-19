# Marionette MCP Example

A multi-page Flutter app demonstrating **`call_custom_extension`** with Marionette MCP.

## App Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Home | Welcome screen |
| `/profile` | Profile | User profile |
| `/testing` | Testing | Native-lane test cases hub |
| `/testing/webview` | WebView | Embedded browser (§2) |
| `/testing/platform-views` | Platform views | Native controls, camera, Google Maps, video (§1) |
| `/testing/permission-dialogs` | Permission dialogs | OS permission prompts (§3) |
| `/testing/pickers-and-sheets` | Pickers & sheets | File, photo, camera, share (§4) |
| `/testing/keyboard` | Keyboard / IME | Numeric, return, done keyboards (§8) |
| `/testing/gestures` | Gestures & inspection | Element state, gestures, waiting, scrolling in containers |
| `/testing/device` | Device & permissions | Every permission group, orientation, deep link query |
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

The app declares camera, photos, microphone, location (when in use), contacts and calendar. The project builds plugins with Swift Package Manager, where `permission_handler_apple` enables a permission only when its usage-description key is in `ios/Runner/Info.plist` (the `PERMISSION_*` macros in `ios/Podfile` apply to CocoaPods builds only). After adding or removing such a key, delete `~/Library/Developer/Xcode/DerivedData/Runner-*` before building — otherwise the permission stays "denied" and no dialog appears.

## Running

```bash
cd example
flutter pub get
flutter run -d macos   # or: flutter run -d chrome
```

Connect via Marionette MCP, then use `call_custom_extension` to navigate.
