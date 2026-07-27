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
| `get_interactive_elements` | List the interactive elements currently visible — each with its type, text, key, identifier (Semantics identifier), and other identifying properties. The agent's primary way to "see" the screen. Optional `ancestor_keys` lists just one subtree. |
| `take_screenshots` | Capture screenshots of all active views, returned as base64 PNGs. |
| `get_logs` | Retrieve app logs collected since start or the last hot reload. Requires a [`LogCollector`](./logging.md). |

### Gestures

| Tool | Description |
| --- | --- |
| `tap` | Tap an element matched by `key`, `identifier`, `text`, `type`, or `coordinates`. Prefer `key`; `identifier` (Semantics identifier) is the next-best stable selector. Tapping a text field focuses it. Optional `ancestor_keys` scopes the search. |
| `secondary_tap` | Right mouse button click on a matching element (**desktop only**); triggers `onSecondaryTap`, e.g. context menus. Match by `key`, `identifier`, `text`, `type`, or `coordinates`. Optional `ancestor_keys` scopes the search. |
| `double_tap` | Double tap an element matched by `key`, `identifier`, `text`, `type`, or `coordinates` (optional `delay` between taps, default 100 ms, and `ancestor_keys`). |
| `long_press` | Long press an element matched by `key`, `identifier`, `text`, `type`, or `coordinates` (optional `duration`, default 600 ms, and `ancestor_keys`) — context menus, reorderable lists. |
| `swipe` | Swipe/drag. Element-based (`key`/`identifier`/`text` + `direction` + optional `distance` and `ancestor_keys`) or coordinate-based (`startX/Y`, `endX/Y`). For `PageView`, `Dismissible`, `Drawer`, sliders. |
| `pinch_zoom` | Pinch to zoom an element matched by `key`, `identifier`, `text`, `type`, or `coordinates` (optional `ancestor_keys`). `scale > 1.0` zooms in, `< 1.0` zooms out. For maps, images, PDFs. |
| `press_back_button` | Simulate the system back button (Android back / iOS swipe-back). Works with Navigator, GoRouter, etc. |
| `scroll_to` | Scroll until an element matching `key`, `identifier`, or `text` becomes visible. Optional `ancestor_keys` scrolls inside one subtree. |

> **Scoping a match with `ancestor_keys`:** every matcher-based tool takes an optional `ancestor_keys` — a list of wrapper `ValueKey<String>`s. The target is searched for inside that subtree only, so a key repeated across identical subtrees (grid cells, repeated cards, embedded app instances) can be disambiguated without baking indices into leaf keys:
>
> ```json
> { "key": "cell.joinButton", "ancestor_keys": ["grid.cell_2"] }
> ```
>
> The keys nest, **outermost first**: each is looked up inside the previous one's subtree. That is what lets you reach a wrapper whose own key also repeats — if every session embeds the same grid, `grid.cell_3` alone would land in the first session:
>
> ```json
> { "key": "cell.joinButton", "ancestor_keys": ["session_2", "grid.cell_3"] }
> ```
>
> If any key in the chain matches no element the call fails — naming the link that broke — rather than falling back to a tree-wide search. It is ignored by `coordinates` and `focused_element`, which do not search the tree.
>
> `get_interactive_elements` takes the same field, but to *list* a subtree rather than match inside one — so you can narrow the listing to one cell and then pass the same chain as `ancestor_keys` to `tap` or `enter_text` to act inside it.

### Text input

| Tool | Description |
| --- | --- |
| `enter_text` | Enter text into a field. Target by `key`, by `identifier`, or focus a field first (via `tap`) and pass `focused_element: true`. Exactly one selector required; optional `ancestor_keys` scopes the search. |
| `press_key` | Press a key on the focused element, producing a real key event (unlike `enter_text`). `key` is a named key (`enter`, `tab`, `escape`, `backspace`, `delete`, `space`, `arrowUp`/`arrowDown`/`arrowLeft`/`arrowRight`, `home`, `end`, `pageUp`, `pageDown`) or a single character `a`-`z`/`0`-`9`. Optional `modifiers` (comma-separated: `control`, `shift`, `alt`, `meta`) for shortcuts like `control,a`. Focus a target first via `tap`. |

> **Platform note for `press_key`:** key events reach `Focus`, `Shortcuts`/`Actions`, and focus traversal on every platform — so app shortcuts, submit (`enter`), dismiss (`escape`), and button activation work everywhere. In-field text editing with `backspace`/arrows/characters relies on Flutter's hardware-key text-editing actions, which are wired on **desktop and web**; on **mobile (iOS/Android)** `TextField` editing is owned by the platform keyboard, so use `enter_text` to change a field's value there.

### Custom extensions

| Tool | Description |
| --- | --- |
| `list_custom_extensions` | List the app-specific extensions registered via `registerMarionetteExtension`. |
| `call_custom_extension` | Call a custom extension that does **not** declare an `inputSchema` (the generic escape hatch), passing key-value args. |

Custom extensions that declare an `inputSchema` are promoted to **first-class, individually-named tools** the agent discovers directly — see [Custom Extensions](./custom-extensions.md).

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
