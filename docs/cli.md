# Marionette CLI

## Why a CLI?

The MCP server works great with tools that support MCP natively (Cursor, Claude Code, etc.), but many enterprise environments restrict which AI models can be used and which protocols are allowed. Not every team can run an MCP server.

The CLI bridges this gap. Any AI agent that can execute shell commands — even smaller, less capable models — can drive a Flutter app through Marionette if given a clear reference document. A well-structured `.md` file describing each command's syntax, expected outputs, and exit codes is often all a constrained agent needs to work autonomously. This makes the CLI the most portable and universally compatible way to integrate Marionette into AI workflows.

> The CLI requires the same Flutter-side setup as the MCP server — your app must initialize `MarionetteBinding`. See [Flutter Setup](./flutter-setup.md).

## Installation

Install globally from [pub.dev](https://pub.dev/packages/marionette_cli):

```bash
dart pub global activate marionette_cli
```

This adds the `marionette` executable to your PATH (ensure `~/.pub-cache/bin` is on your PATH).

## Teaching AI agents to use the CLI

For an agent to use the CLI effectively, it needs a reference describing every command, its arguments, expected outputs, and exit codes. The `help-ai` command prints exactly that — a comprehensive, machine-readable reference designed for AI consumption:

```bash
marionette help-ai
```

Have the agent run this once at the start of a session, capture the output, and use it as a guide. You can also pipe it to a file and include it as a Cursor rule, an Agent Skill (`SKILL.md`), or a system prompt:

```bash
marionette help-ai > .cursor/rules/marionette-cli.md
```

## Direct URI mode (stateless)

Pass the VM service URI directly with `--uri` — no registration, no cleanup, no files on disk:

```bash
marionette --uri ws://127.0.0.1:8181/ws get-interactive-elements
marionette --uri ws://127.0.0.1:8181/ws tap --key submit_button
marionette --uri ws://127.0.0.1:8181/ws take-screenshots --output ./screenshot.png
marionette --uri ws://127.0.0.1:8181/ws record-video --output ./recording.webm
```

`--uri` and `--instance` are mutually exclusive. Use `--uri` for one-off interactions and `--instance` when targeting the same app repeatedly.

## Named instance mode (stateful)

For repeated interactions, register the app once under a name so you don't repeat the URI:

```bash
# Register Flutter app instances (use the VM service URI from `flutter run`)
marionette register my-app ws://127.0.0.1:8181/ws
marionette register other-app ws://127.0.0.1:9090/ws

# Interact with a specific instance
marionette -i my-app get-interactive-elements
marionette -i my-app tap --key submit_button
marionette -i my-app tap --identifier submit_button
marionette -i my-app tap --text "Submit"
marionette -i my-app enter-text --key email_field --input "test@example.com"
marionette -i my-app scroll-to --text "Bottom Item"
marionette -i my-app swipe --type PageView --direction left
marionette -i my-app take-screenshots --output ./screenshot.png
marionette -i my-app record-video --output ./recording.webm
marionette -i my-app record-video -o ./demo.webm -d 10
marionette -i my-app get-logs
marionette -i my-app hot-reload
marionette -i my-app hot-restart

# Instance management
marionette list
marionette unregister my-app
marionette doctor              # Check connectivity of all instances
```

## Native lane (system UI)

Permission dialogs, system alerts, share sheets, pickers, notifications, browser sign-in, biometric prompts, native screens and WebView content are outside the Flutter widget tree. The `native-*` commands reach them — the same tools as the MCP server's `native_*` tools (UIAutomator2 on Android, WebDriverAgent on an iOS Simulator), with the same behaviour and messages.

```bash
marionette native-connect --platform android          # or: --platform ios [--udid <udid>]
marionette native-wait-for --text "Allow" --timeout-ms 5000
marionette native-tap --text "Allow"
marionette native-get-elements --clickable-only       # JSON
marionette native-permissions --action grant --permission camera
marionette native-take-screenshot --output ./system.png
marionette native-disconnect
```

`native-connect` starts the device-side server detached from the CLI, so it keeps running between commands, and saves the session in `~/.marionette/native/<name>.json`. Every `native-*` command attaches to it and reuses the WebDriver session — no per-command setup. `native-disconnect` stops the server it started. Use `--native-session <name>` to drive several devices at once (e.g. an Android phone and an iPhone in one script); `native-sessions` lists them. Use one client per Android device at a time: UIAutomator2 has a single session, so an MCP server and a CLI session on the same device take it from each other (`native-connect` warns when it reuses another process's server). `marionette doctor` also checks the native lane: adb and devices, the UIAutomator2 APKs (checksum of the cached copies), booted simulators, the WebDriverAgent build, port 8100 taken by another program, orphaned servers and sessions whose server is gone. Design and measurements: [D4](./native-lane-decisions.md#d4).

`native-map-flutter-rect` combines both lanes: pass `-i <instance>` or `--uri` to convert bounds from `get-interactive-elements` into native screenshot pixels for a gesture on a platform view.

## Command reference

Global options: `-i, --instance <name>`, `--uri <ws://...>`, `--timeout <seconds>` (default 5), `--native-session <name>` (default `default`, for `native-*` commands).

| Command | Purpose |
| --- | --- |
| `get-interactive-elements` | List interactive UI elements. |
| `tap` | Tap an element (`--key`, `--identifier`, `--text`, `--type`, or `--x`/`--y`). |
| `secondary-tap` | Right-click a matching element (desktop only) (`--key`, `--identifier`, `--text`, `--type`, or `--x`/`--y`). |
| `double-tap` | Double tap (`--key`, `--identifier`, `--text`, `--type`, or `--x`/`--y`, plus `--delay`). |
| `long-press` | Long press (`--key`, `--identifier`, `--text`, `--type`, or `--x`/`--y`, plus `--duration`). |
| `pinch-zoom` | Pinch zoom (`--key`, `--identifier`, `--text`, `--type`, or `--x`/`--y`, plus `--scale`, `--start-distance`). |
| `swipe` | Swipe/drag (`--key`/`--identifier`/`--text` + `--direction`, `--distance`, or `--start-x`/`--start-y`/`--end-x`/`--end-y`). |
| `enter-text` | Enter text (`--key`, `--identifier`, `--text`, or `--focused`, plus `--input`). |
| `press-key` | Press a key on the focused element (`--key`, optional `--modifiers`). Real key event: enter to submit, tab to move focus, escape, arrows/backspace to edit, or `--modifiers control` for shortcuts. |
| `scroll-to` | Scroll to an element (`--key`, `--identifier`, or `--text`). |
| `press-back-button` | Simulate the system back button. |
| `take-screenshots` | Capture a screenshot (`-o/--output`, `--open`). |
| `record-video` | Record video (`-o/--output`, `-d/--duration`, `--width`, `--height`, `--ffmpeg-path`, `--open`, …). |
| `get-logs` | Retrieve app logs. |
| `hot-reload` | Hot reload the app. |
| `hot-restart` | Hot restart the app — restart from `main()`, resetting all state. |
| `register <name> <uri>` | Register a named instance. |
| `unregister [<name>` &#124; `--all` &#124; `--stale]` | Remove instance(s). |
| `list` | List registered instances. |
| `doctor` | Check connectivity of all instances and the native lane setup. |
| `help-ai` | Print the AI-oriented command reference. |
| `mcp` | Run the MCP server (`-l/--log-level`, `--log-file`, `--sse-port`). |
| `native-connect` | Start a native session (`--platform android\|ios`, `--serial`, `--udid`). |
| `native-disconnect` | End the native session; stop the server it started. |
| `native-sessions` | List native sessions and whether their servers run. |
| `native-get-elements` | Native UI tree as JSON (selector filters, `--clickable-only`, `--no-include-foreground-app`). |
| `native-wait-for` | Wait until an element is visible / gone (`--state`, `--timeout-ms`, `--interval-ms`). |
| `native-tap`, `native-double-tap`, `native-long-press` | Gesture on an element (`--text`, `--text-contains`, `--id`, `--type`, `--index`) or at `--x`/`--y` (screenshot pixels). |
| `native-pinch` | Two-finger pinch (`--scale`, element or point). |
| `native-swipe` | Swipe between points (`--start-x`, `--start-y`, `--end-x`, `--end-y`, `--duration-ms`). |
| `native-scroll` | Swipe in `--direction`, optionally until a target is visible; `--within-*` scrolls a container. |
| `native-enter-text` | Type `--text` into a field (`--label`, `--text-contains`, `--id`, `--type`, `--index`) or the focused one; `--clear`. |
| `native-press-key`, `native-hide-keyboard` | System keys; hide the software keyboard. |
| `native-take-screenshot` | Screenshot of the screen or an element (`-o/--output`). |
| `native-device-info` | Device facts as JSON. |
| `native-permissions` | Grant / revoke / reset a permission without the dialog. |
| `native-open-url` | Open a web page or deep link. |
| `native-app` | Activate / background / terminate / restart an app. |
| `native-notifications` | Open / close notifications; simulated push (iOS). |
| `native-set-orientation`, `native-set-location` | Rotate; simulated GPS position. |
| `native-biometrics` | Simulated Face ID / Touch ID / fingerprint (`match`, `nonMatch`, `enroll`, `unenroll`). |
| `native-map-flutter-rect` | Flutter bounds → native screenshot pixels (needs `-i`/`--uri`). |
