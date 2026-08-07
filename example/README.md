# Marionette MCP Example

A multi-page Flutter app demonstrating **`call_custom_extension`** with Marionette MCP.

## App Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Home | Welcome screen |
| `/profile` | Profile | User profile |
| `/testing` | Testing | Native-lane test cases hub |
| `/testing/permission-dialogs` | Permission dialogs | OS permission prompts (§3) |
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

## Running

```bash
cd example
flutter pub get
flutter run -d macos   # or: flutter run -d chrome
```

Connect via Marionette MCP, then use `call_custom_extension` to navigate.
