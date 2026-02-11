# Marionette MCP Example

A multi-page Flutter app demonstrating **`call_custom_extension`** with Marionette MCP.

## App Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Home | Welcome screen |
| `/profile` | Profile | User profile |
| `/settings` | Settings | Settings with link to Notifications |
| `/settings/notifications` | Notifications | Nested page (2 taps via UI) |

## Custom VM Service Extensions

### `appNavigation.getPageInfo`

Returns the current page and all available pages.

```
call_custom_extension(
  extension: "appNavigation.getPageInfo"
)
→ {"status":"Success","currentPage":"home","currentPath":"/","availablePages":["home","profile","settings","notifications"]}
```

### `appNavigation.goToPage`

Navigate directly to any page by name — even nested pages that require multiple UI taps.

```
call_custom_extension(
  extension: "appNavigation.goToPage",
  args: { page: "notifications" }
)
→ {"status":"Success","page":"notifications","path":"/settings/notifications"}
```

## Why `call_custom_extension` Matters

The Notifications page is nested under Settings. Via the UI, reaching it requires:

1. Tap the Settings tab
2. Tap the Notifications list tile

With `call_custom_extension`, an AI agent can jump there in a single call — no multi-step UI interaction needed.

## Running

```bash
cd example
flutter pub get
flutter run -d macos   # or: flutter run -d chrome
```

Connect via Marionette MCP, then use `call_custom_extension` to navigate.
