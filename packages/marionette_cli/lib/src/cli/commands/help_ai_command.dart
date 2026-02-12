import 'dart:io';

import 'package:args/command_runner.dart';

class HelpAiCommand extends Command<int> {
  @override
  String get name => 'help-ai';

  @override
  String get description =>
      'Print a comprehensive CLI reference designed for AI agent consumption.';

  @override
  int run() {
    stdout.writeln(_reference);
    return 0;
  }
}

const _reference = r'''
# Marionette CLI — AI Agent Reference

Marionette CLI controls Flutter apps running in debug mode. It supports
multiple simultaneous app instances via a named instance registry, or direct
URI connections for fully stateless operation.

## Workflow

### Option A: Named Instances (stateful)

1. Start your Flutter app(s) in debug mode and note VM service URI(s)
   (printed in console, e.g., ws://127.0.0.1:XXXXX/ws).
2. Register each app: `marionette register <name> <uri>`
3. Interact using: `marionette -i <name> <command> [args]`
4. Clean up when done: `marionette unregister <name>`

### Option B: Direct URI (stateless)

1. Start your Flutter app in debug mode and note the VM service URI.
2. Interact directly: `marionette --uri <ws-uri> <command> [args]`

No registration, no cleanup, no files on disk. Each command opens a fresh
WebSocket connection, executes, and disconnects.

## Global Options

  -i, --instance <name>    Target instance (required unless --uri is used)
      --uri <ws-uri>       VM service WebSocket URI — bypasses registry,
                           mutually exclusive with --instance
      --timeout <seconds>  Connection timeout (default: 5)

## Commands

### register <name> <uri>

Register a Flutter app instance.

  Arguments:
    name   Alphanumeric identifier [a-zA-Z0-9_-]+
    uri    VM service WebSocket URI (e.g., ws://127.0.0.1:8181/ws)

  Example:
    marionette register my-app ws://127.0.0.1:8181/ws

  Output (stdout):
    Registered instance "my-app" → ws://127.0.0.1:8181/ws

  Output if overwriting (stderr):
    Updated existing instance "my-app" → ws://127.0.0.1:8181/ws

  Exit codes: 0 success, 64 invalid name/usage

---

### unregister <name>

Remove a registered instance.

  Arguments:
    name   Instance name to remove

  Example:
    marionette unregister my-app

  Output (stdout):
    Unregistered instance "my-app".

  Output if not found (stderr, exit 1):
    Instance "my-app" not found.

---

### list

List all registered instances.

  Example:
    marionette list

  Output (stdout):
    Registered instances:

      my-app
        URI: ws://127.0.0.1:8181/ws
        Registered: 2026-02-12 15:30:00.000

  Output if empty (stdout):
    No instances registered.

---

### elements

List interactive UI elements in the app's widget tree.

  Requires: -i <instance> or --uri <ws-uri>

  Examples:
    marionette -i my-app elements
    marionette --uri ws://127.0.0.1:8181/ws elements

  Output (stdout), one line per element:
    Found 3 interactive element(s):

    Type: ElevatedButton, Key: "submit_button", Text: "Submit"
    Type: TextField, Key: "email_field"
    Type: IconButton, Text: ""

  Each element may have: type, key, text, and additional properties.
  Use the key or text values as matchers for tap, enter-text, scroll-to.

---

### tap

Tap an element. Provide exactly one matching strategy.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    --key <string>    Match by ValueKey<String> (most reliable)
    --text <string>   Match by visible text content
    --type <string>   Match by widget type name (e.g., ElevatedButton)
    --x <number>      X screen coordinate (use with --y)
    --y <number>      Y screen coordinate (use with --x)

  Examples:
    marionette -i my-app tap --key submit_button
    marionette -i my-app tap --text "Submit"
    marionette --uri ws://127.0.0.1:8181/ws tap --key submit_button
    marionette -i my-app tap --x 100 --y 200

  Output (stdout):
    Tapped element matching {key: submit_button}

---

### enter-text

Enter text into a text field.

  Requires: -i <instance> or --uri <ws-uri>

  Options (all required):
    --key <string>      Match text field by key (or use --text)
    --text <string>     Match text field by visible text
    --input <string>    Text to enter (mandatory)

  Example:
    marionette -i my-app enter-text --key email_field --input "user@example.com"

  Output (stdout):
    Entered text into element matching {key: email_field}

---

### scroll-to

Scroll until an element becomes visible.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    --key <string>    Match by ValueKey<String>
    --text <string>   Match by visible text content

  Example:
    marionette -i my-app scroll-to --text "Bottom Item"

  Output (stdout):
    Scrolled to element matching {text: Bottom Item}

---

### screenshot

Capture screenshots and save to PNG files.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    -o, --output <path>   Output file path (mandatory)
    --open                Open the file after saving

  Example:
    marionette -i my-app screenshot --output ./screenshot.png

  Output (stdout):
    Saved screenshot: ./screenshot.png

  Multi-view apps produce numbered files:
    Saved screenshot: ./screenshot.png
    Saved screenshot: ./screenshot_1.png

---

### logs

Retrieve collected application logs.

  Requires: -i <instance> or --uri <ws-uri>

  Example:
    marionette -i my-app logs

  Output (stdout):
    Collected 5 log entries:

    [INFO] App started
    [DEBUG] Loading data...
    ...

  Output if empty (stdout):
    No logs collected.

---

### hot-reload

Perform a hot reload of the Flutter app.

  Requires: -i <instance> or --uri <ws-uri>

  Example:
    marionette -i my-app hot-reload

  Output (stdout, exit 0):
    Hot reload completed successfully.

  Output on failure (stderr, exit 1):
    Hot reload failed. The app may need a full restart.

---

### doctor

Check connectivity of all registered instances.

  Example:
    marionette doctor

  Output (stdout):
    Checking 2 instance(s)...

      my-app (ws://127.0.0.1:8181/ws) ... OK
      other-app (ws://127.0.0.1:9090/ws) ... FAILED

    Some instances are unreachable. Use "marionette unregister <name>" to remove stale entries.

  Exit codes: 0 all reachable, 1 any unreachable

---

### mcp

Run the Marionette MCP server (preserves original marionette_mcp behavior).

  Options:
    -l, --log-level <level>   FINEST|FINER|FINE|CONFIG|INFO|WARNING|SEVERE (default: INFO)
    --log-file <path>         Log file path (default: stderr)
    --sse-port <port>         Use SSE transport on this port (default: stdio)

  Example:
    marionette mcp
    marionette mcp --sse-port 3000

---

## Exit Codes

  0    Success
  1    Runtime error (connection failed, command failed, app unreachable)
  64   Usage error (missing arguments, invalid options)

## Error Recovery

If a command fails with a connection error, the app may have stopped.

- **--instance mode**: Run `marionette doctor` to check all instances, then
  `marionette unregister <name>` to clean up stale entries.
- **--uri mode**: Verify the URI is correct and the app is still running.
  Re-run `flutter run` if needed and use the new URI.

## Tips

- Prefer --uri for one-off interactions (no setup/cleanup overhead)
- Prefer --instance for repeated interactions with the same app (shorter commands)
- Prefer --key over --text for matching elements (keys are stable, text may change)
- Run `elements` first to discover what's on screen before interacting
- Instance names are alphanumeric with hyphens/underscores: [a-zA-Z0-9_-]+
- Commands are stateless — each opens a fresh connection, so no session management needed
''';
