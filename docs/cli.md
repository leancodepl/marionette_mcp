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
marionette -i my-app tap --text "Submit"
marionette -i my-app enter-text --key email_field --input "test@example.com"
marionette -i my-app scroll-to --text "Bottom Item"
marionette -i my-app swipe --type PageView --direction left
marionette -i my-app take-screenshots --output ./screenshot.png
marionette -i my-app record-video --output ./recording.webm
marionette -i my-app record-video -o ./demo.webm -d 10
marionette -i my-app get-logs
marionette -i my-app hot-reload

# Instance management
marionette list
marionette unregister my-app
marionette doctor              # Check connectivity of all instances
```

## Command reference

Global options: `-i, --instance <name>`, `--uri <ws://...>`, `--timeout <seconds>` (default 5).

| Command | Purpose |
| --- | --- |
| `get-interactive-elements` | List interactive UI elements. |
| `tap` | Tap an element (`--key`, `--text`, `--type`, or `--x`/`--y`). |
| `secondary-tap` | Right-click a matching element (desktop only). |
| `double-tap` | Double tap (matchers + `--delay`). |
| `long-press` | Long press (matchers + `--duration`). |
| `pinch-zoom` | Pinch zoom (matchers + `--scale`, `--start-distance`). |
| `swipe` | Swipe/drag (matchers + `--direction`, `--distance`, or `--start-x`/`--start-y`/`--end-x`/`--end-y`). |
| `enter-text` | Enter text (`--key` or `--focused`, plus `--input`). |
| `scroll-to` | Scroll to an element (`--key` or `--text`). |
| `press-back-button` | Simulate the system back button. |
| `take-screenshots` | Capture a screenshot (`-o/--output`, `--open`). |
| `record-video` | Record video (`-o/--output`, `-d/--duration`, `--width`, `--height`, `--ffmpeg-path`, `--open`, …). |
| `get-logs` | Retrieve app logs. |
| `hot-reload` | Hot reload the app. |
| `register <name> <uri>` | Register a named instance. |
| `unregister [<name>` &#124; `--all` &#124; `--stale]` | Remove instance(s). |
| `list` | List registered instances. |
| `doctor` | Check connectivity of all instances. |
| `help-ai` | Print the AI-oriented command reference. |
| `mcp` | Run the MCP server (`-l/--log-level`, `--log-file`, `--sse-port`). |
