# Marionette MCP Example

A multi-page Flutter app demonstrating **`call_custom_extension`** with Marionette MCP.

## App Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Home | Welcome screen |
| `/profile` | Profile | User profile |
| `/settings` | Settings | Settings with link to Notifications |
| `/settings/notifications` | Notifications | Nested page (2 taps via UI) |
| `/settings/custom-widgets` | Custom Widgets | Custom design-system widgets recognized via `MarionetteConfiguration` |

## Custom Widgets

`lib/custom_widgets.dart` is a tiny stand-in for an app's design system. `main.dart` teaches Marionette about it:

- `isInteractiveElement` matches every `DsButton` subclass and every `DsSelect<T>` with an `is` check, and marks a `DsTile` interactive only when it has an `onTap`.
- `shouldStopTraversalAtElement` skips the internals of `DsSelect`, whose label comes from `extractText`.

The same page shows built-in generic widgets (`DropdownButton<String>`, `Radio<int>`, `RadioListTile<int>`, `PopupMenuButton<String>`) that Marionette recognizes without any configuration.

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
