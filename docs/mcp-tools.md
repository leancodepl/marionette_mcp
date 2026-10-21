# MCP Tools

Once your agent is connected (see [Configuring your AI tool](#configuring-your-ai-tool)), it has access to the tools below. Marionette keeps the surface area intentionally small and high-signal: a handful of actions that return the minimum actionable data, to keep prompts focused and context sizes under control.

## Tool reference

### Connection

| Tool | Description |
| --- | --- |
| `connect` | Connect to a Flutter app via its VM service URI (e.g. `ws://127.0.0.1:8181/ws`). Must be called before any other tool. Verifies the `marionette_flutter` binding version matches the server. |
| `disconnect` | Disconnect from the currently connected app. |

### Inspection

| Tool | Description |
| --- | --- |
| `get_interactive_elements` | List the interactive elements currently visible — each with its type, text, key, identifier (Semantics identifier), and other identifying properties. The agent's primary way to "see" the screen. Starts with a warning when the app is not in front — system UI or another screen covers it ([D22](./native-lane-decisions.md#d22)). |
| `take_screenshots` | Returns base64-encoded inline PNGs for all active views (default — no files written). When `MARIONETTE_SCREENSHOTS_DIR` is set, also saves PNG files to that directory and includes the absolute paths in the response alongside the inline images. |
| `get_logs` | Retrieve app logs collected since start or the last hot reload. Requires a [`LogCollector`](./logging.md). |

### Gestures

| Tool | Description |
| --- | --- |
| `tap` | Tap an element matched by `key`, `identifier`, `text`, `type`, or `coordinates`. Prefer `key`; `identifier` (Semantics identifier) is the next-best stable selector. Tapping a text field focuses it. |
| `secondary_tap` | Right mouse button click on a matching element (**desktop only**); triggers `onSecondaryTap`, e.g. context menus. Match by `key`, `identifier`, `text`, `type`, or `coordinates`. |
| `double_tap` | Double tap an element matched by `key`, `identifier`, `text`, `type`, or `coordinates` (optional `delay` between taps, default 100 ms). |
| `long_press` | Long press an element matched by `key`, `identifier`, `text`, `type`, or `coordinates` (optional `duration`, default 600 ms) — context menus, reorderable lists. |
| `swipe` | Swipe/drag. Element-based (`key`/`identifier`/`text` + `direction` + optional `distance` + optional `startX`/`startY`) or coordinate-based (`startX/Y`, `endX/Y`). For `PageView`, `Dismissible`, `Drawer`, sliders. |
| `pinch_zoom` | Pinch to zoom an element matched by `key`, `identifier`, `text`, `type`, or `coordinates`. `scale > 1.0` zooms in, `< 1.0` zooms out. For maps, images, PDFs. |
| `press_back_button` | Simulate the system back button (Android back / iOS swipe-back). Works with Navigator, GoRouter, etc. |
| `scroll_to` | Scroll until an element matching `key`, `identifier`, or `text` becomes visible. |

### Text input

| Tool | Description |
| --- | --- |
| `enter_text` | Enter text into a field. Target by `key`, by `identifier`, or focus a field first (via `tap`) and pass `focused_element: true`. Exactly one selector required. |
| `press_key` | Press a key on the focused element, producing a real key event (unlike `enter_text`). `key` is a named key (`enter`, `tab`, `escape`, `backspace`, `delete`, `space`, `arrowUp`/`arrowDown`/`arrowLeft`/`arrowRight`, `home`, `end`, `pageUp`, `pageDown`) or a single character `a`-`z`/`0`-`9`. Optional `modifiers` (comma-separated: `control`, `shift`, `alt`, `meta`) for shortcuts like `control,a`. Focus a target first via `tap`. |

> **Platform note for `press_key`:** key events reach `Focus`, `Shortcuts`/`Actions`, and focus traversal on every platform — so app shortcuts, submit (`enter`), dismiss (`escape`), and button activation work everywhere. In-field text editing with `backspace`/arrows/characters relies on Flutter's hardware-key text-editing actions, which are wired on **desktop and web**; on **mobile (iOS/Android)** `TextField` editing is owned by the platform keyboard, so use `enter_text` to change a field's value there.

### Custom extensions

| Tool | Description |
| --- | --- |
| `list_custom_extensions` | List the app-specific extensions registered via `registerMarionetteExtension`. |
| `call_custom_extension` | Call a custom extension that does **not** declare an `inputSchema` (the generic escape hatch), passing key-value args. |

Custom extensions that declare an `inputSchema` are promoted to **first-class, individually-named tools** the agent discovers directly — see [Custom Extensions](./custom-extensions.md).

### Native lane

Tools for system / native UI outside the Flutter widget tree (permission dialogs, OS sheets and pickers, embedded WebViews, native views, notifications). Setup, workflow and what each lane sees: [Native lane](./native-lane.md). All native tools use the `native_` prefix. Call `native_connect` first.

| Tool | Description |
| --- | --- |
| `native_connect` | Start a native automation session (UIAutomator2 on Android, WebDriverAgent on iOS). Requires `platform`: `android` or `ios`. If the device-side server or session is lost later, call it again. |
| `native_disconnect` | Stop the native session and release device-side processes. |
| `native_get_elements` | Return the native UI hierarchy as JSON (`elements`, optional `foregroundApp`). `bounds` are in screenshot pixels on every platform ([D2](./native-lane-decisions.md#d2)). State is included when it carries information: `value` (a text field's content — its `text` stays the label), `enabled: false`, `focused: true` (Android), `checked`, `selected: true`, `scrollable: true`. Optional filters: `text`, `textContains`, `id`, `type`, `clickableOnly`; `includeForegroundApp: false` skips the foreground app ([D15](./native-lane-decisions.md#d15)). Only on-screen elements are listed; on iOS partly visible ones are clipped to the screen, as on Android ([D16](./native-lane-decisions.md#d16)). |
| `native_wait_for` | Wait until an element matching a selector is visible (`state: visible`, default; returns it) or `gone`. `timeoutMs` default 10000 (max 60000), `intervalMs` default 500. A timeout names the foreground app ([D16](./native-lane-decisions.md#d16)). |
| `native_tap` | Tap an element chosen by a selector (`text`, `textContains`, `id`, `type`, optional `index`) or at `x`/`y` in screenshot pixels. An ambiguous selector fails and lists the candidates ([D1](./native-lane-decisions.md#d1)). |
| `native_scroll` | Swipe in a `direction` from screen center (default), inside a container (`within`: a selector) or from `startX`/`startY`; optionally scroll until an element matching `text` / `textContains` / `id` / `type` is visible, up to `maxSwipes` (default 10). Searching uses slow drags so the list does not fling past the target, waits for the content to settle, and stops early when the content no longer moves (end of the list) ([D16](./native-lane-decisions.md#d16)). |
| `native_swipe` | Swipe one finger from `startX`/`startY` to `endX`/`endY` (screenshot pixels) over `durationMs` (default 300) — drags, sliders, edge gestures (iOS back: start at `x=1`). |
| `native_enter_text` | Type `text` into a native field chosen by a selector (`label`, `textContains`, `id`, `type`, optional `index`), or — without a selector — into the field that has keyboard focus. Text is appended; `clear: true` empties the field first; a field that changed before anything was typed is found again once. `label` also matches the first line of a field's label ([D14](./native-lane-decisions.md#d14), [D15](./native-lane-decisions.md#d15)). |
| `native_press_key` | Press a system / hardware key: `back`, `home`, `enter`, `backspace`, `tab`, `recents`, `volume_up`, `volume_down`. `back`, `recents` and `tab` are Android-only; the iOS Simulator has only `home` of the hardware buttons. |
| `native_hide_keyboard` | Hide the software keyboard if it is shown and report whether it was. Android presses Back only while the keyboard is shown; iOS uses the keyboard's Done / dismiss key and fails with a hint when there is none; Android fails with a hint when only Gboard's floating toolbar is shown (hardware keyboard attached), because Back would close the screen ([D14](./native-lane-decisions.md#d14)). |
| `native_take_screenshot` | Returns a base64 inline PNG of the full device screen via the native session (system UI, WebViews). When `MARIONETTE_SCREENSHOTS_DIR` is set, also saves the PNG to that directory and includes the absolute path alongside the inline image. |
| `native_notifications` | `open` / `close` the notification shade (Android) or Notification Center (iOS, by swipe). Open a notification with `native_tap` (Android, iOS banner); in the iOS Notification Center a tap does nothing — swipe it right with `native_swipe`; a collapsed "N Notifications" button must be tapped first ([D21](./native-lane-decisions.md#d21)). Android heads-up banners are not in the tree — read them with `native_take_screenshot`. Toasts: on older Android (seen on API 28) listed read-only by `native_get_elements` / `native_wait_for` (`android.widget.Toast`, no bounds, cannot be tapped); on recent Android (API 35) not listed, and a tree read waits until the toast is gone ([D19](./native-lane-decisions.md#d19)). |

### Dev workflow

| Tool | Description |
| --- | --- |
| `hot_reload` | Hot reload the app — apply code changes without losing state. |
| `hot_restart` | Hot restart the app — fully restart from `main()`, resetting all state. Requires `flutter run`. |

## How it works

1. **Initialization** — your app initializes `MarionetteBinding`, which registers custom VM service extensions (`ext.flutter.marionette.*`).
2. **Connection** — the MCP server connects to your app's VM Service URL and checks that the binding version matches.
3. **Interaction** — when the agent calls a tool (e.g. `tap`), the server translates it into a call to the corresponding VM service extension.
4. **Execution** — the Flutter app performs the action (e.g. simulates a tap gesture) and returns the result.

## Configuring your AI tool

Install the server as a global tool first:

```bash
dart pub global activate marionette_mcp
```

> Prefer a dev-dependency? Run `dart pub add dev:marionette_mcp` and invoke the server as `dart run marionette_mcp` (you may need to `cd` into the package directory so `dart run` resolves it). If that's fiddly, the global tool is the simplest path.

Then register it with your tool:

### Claude Code

```bash
claude mcp add --transport stdio marionette -- marionette_mcp
```

### Codex

```bash
codex mcp add marionette -- marionette_mcp
```

### Cursor

[![Install MCP Server](https://cursor.com/deeplink/mcp-install-dark.svg)](https://cursor.com/en-US/install-mcp?name=marionette&config=eyJlbnYiOnt9LCJjb21tYW5kIjoibWFyaW9uZXR0ZV9tY3AgIn0%3D)

Or add to your project's `.cursor/mcp.json` (or global `~/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "marionette": { "command": "marionette_mcp", "args": [] }
  }
}
```

### Google Antigravity

Open the MCP store → "Manage MCP Servers" → "View raw config", and add to `mcp_config.json`:

```json
{
  "mcpServers": {
    "marionette": { "command": "marionette_mcp", "args": [] }
  }
}
```

### Gemini CLI

Add to `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "marionette": { "command": "marionette_mcp", "args": [] }
  }
}
```

### Copilot

Add to your `mcp.json`:

```json
{
  "servers": {
    "marionette": { "command": "marionette_mcp", "args": [] }
  }
}
```

> Can't run an MCP server (enterprise restrictions, an agent that only runs shell commands)? Use the [CLI](./cli.md) instead.
