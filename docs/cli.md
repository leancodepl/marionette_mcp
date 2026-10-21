# Marionette CLI

This page moved to the Marionette website:

- [Drive: the CLI](https://marionette.leancode.co/docs/drive#cli)

The native lane (`native-*` commands) is documented here until it moves to the website.

## Native lane (system UI)

Permission dialogs, system alerts, share sheets, pickers, notifications, browser sign-in, native screens and WebView content are outside the Flutter widget tree. The `native-*` commands reach them — the same tools as the MCP server's `native_*` tools (UIAutomator2 on Android, WebDriverAgent on an iOS Simulator), with the same behaviour and messages.

```bash
marionette native-connect --platform android          # or: --platform ios [--udid <udid>]
marionette native-wait-for --text "Allow" --timeout-ms 5000
marionette native-tap --text "Allow"
marionette native-get-elements --clickable-only       # JSON
marionette native-take-screenshot --output ./system.png
marionette native-disconnect
```

`native-connect` starts the device-side server detached from the CLI, so it keeps running between commands, and saves the session in `~/.marionette/native/<name>.json`. Every `native-*` command attaches to it and reuses the WebDriver session — no per-command setup. `native-disconnect` stops the server it started. Use `--native-session <name>` to drive several devices at once (e.g. an Android phone and an iPhone in one script); `native-sessions` lists them. Prefer one client per Android device at a time: UIAutomator2 has a single session, so an MCP server and a CLI session on the same device take it from each other — the CLI opens a new session for its next command, the MCP server needs `native_connect` again (`native-connect` warns when it reuses another process's server).

`--native-session <name>` (default `default`) is a global option, given before the command.

| Command | Description |
| --- | --- |
| `native-connect` | Start a native session (`--platform android\|ios`, `--serial`, `--udid`). |
| `native-disconnect` | End the native session; stop the server it started. |
| `native-sessions` | List native sessions and whether their servers run. |
| `native-get-elements` | Native UI tree as JSON (selector filters, `--clickable-only`, `--no-include-foreground-app`). |
| `native-wait-for` | Wait until an element is visible / gone (`--state`, `--timeout-ms`, `--interval-ms`). |
| `native-tap` | Tap an element (`--text`, `--text-contains`, `--id`, `--type`, `--index`) or at `--x`/`--y` (screenshot pixels). |
| `native-swipe` | Swipe between points (`--start-x`, `--start-y`, `--end-x`, `--end-y`, `--duration-ms`). |
| `native-scroll` | Swipe in `--direction`, optionally until a target is visible; `--within-*` scrolls a container. |
| `native-enter-text` | Type `--text` into a field (`--label`, `--text-contains`, `--id`, `--type`, `--index`) or the focused one; `--clear`. |
| `native-press-key`, `native-hide-keyboard` | System keys; hide the software keyboard. |
| `native-take-screenshot` | Screenshot of the screen (`-o/--output`). |
| `native-notifications` | Open / close notifications. |
