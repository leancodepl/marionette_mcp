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
      --native-session <name>
                           Native session for native-* commands
                           (default: "default")

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

### get-interactive-elements

List interactive UI elements in the app's widget tree.

  Requires: -i <instance> or --uri <ws-uri>

  Examples:
    marionette -i my-app get-interactive-elements
    marionette --uri ws://127.0.0.1:8181/ws get-interactive-elements

  Output (stdout), one line per element:
    Found 3 interactive element(s):

    Type: ElevatedButton, Key: "submit_button", Text: "Submit"
    Type: TextField, Key: "email_field"
    Type: IconButton, Text: ""

  Each element may have: type, key, text, identifier, and additional
  properties. Use the key, identifier, or text values as matchers for tap,
  enter-text, scroll-to.

---

### tap

Tap an element. Provide exactly one matching strategy.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    --key <string>        Match by ValueKey<String> (most reliable)
    --identifier <string> Match by Semantics identifier (stable alternative)
    --text <string>       Match by visible text content
    --type <string>       Match by widget type name (e.g., ElevatedButton)
    --x <number>          X screen coordinate (use with --y)
    --y <number>          Y screen coordinate (use with --x)

  Examples:
    marionette -i my-app tap --key submit_button
    marionette -i my-app tap --identifier submit_button
    marionette -i my-app tap --text "Submit"
    marionette --uri ws://127.0.0.1:8181/ws tap --key submit_button
    marionette -i my-app tap --x 100 --y 200

  Output (stdout):
    Tapped element matching {key: submit_button}

---

### secondary-tap

Secondary (right mouse button) tap an element. Desktop only — triggers
Flutter's onSecondaryTap (e.g. context menus). Provide exactly one matching
strategy.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    --key <string>        Match by ValueKey<String> (most reliable)
    --identifier <string> Match by Semantics identifier (stable alternative)
    --text <string>       Match by visible text content
    --type <string>       Match by widget type name (e.g., ElevatedButton)
    --x <number>          X screen coordinate (use with --y)
    --y <number>          Y screen coordinate (use with --x)

  Examples:
    marionette -i my-app secondary-tap --key file_item
    marionette -i my-app secondary-tap --identifier file_item
    marionette -i my-app secondary-tap --text "Document"
    marionette -i my-app secondary-tap --x 100 --y 200

  Output (stdout):
    Secondary tapped element matching {key: file_item}

---

### enter-text

Enter text into a text field.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    --key <string>        Match text field by key
    --identifier <string> Match text field by Semantics identifier
    --text <string>       Match text field by visible text
    --focused             Target the currently focused text field
    --input <string>      Text to enter (mandatory)

  Example:
    marionette -i my-app enter-text --key email_field --input "user@example.com"
    marionette -i my-app enter-text --identifier email_field --input "user@example.com"

  Output (stdout):
    Entered text into element matching {key: email_field}

---

### press-key

Press a keyboard key on the currently focused element. Unlike enter-text
(which rewrites a field's value), this sends a real key event through the focus
system, so onSubmitted, Shortcuts/Actions, and focus traversal all respond.
The key goes to whatever has focus — focus a target first (e.g. with tap).

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    --key <string>        Key to press (mandatory). Named keys: enter, tab,
                          escape, backspace, delete, space, arrowUp, arrowDown,
                          arrowLeft, arrowRight, home, end, pageUp, pageDown.
                          Also a single character a-z or 0-9.
    --modifiers <list>    Comma-separated modifiers to hold: control, shift,
                          alt, meta. On macOS use meta for the Command key.

  Examples:
    marionette -i my-app press-key --key enter
    marionette -i my-app press-key --key tab
    marionette -i my-app press-key --key a --modifiers control
    marionette --uri ws://127.0.0.1:8181/ws press-key --key arrowDown

  Output (stdout):
    Pressed key: enter
    Pressed key: control+a

  Notes:
    - A character is only typed for an unmodified (or shift-only) printable
      key; control+a activates select-all rather than typing "a".
    - Modifier combos match Flutter Shortcuts/SingleActivator.

---

### press-back-button

Simulate a system back button press (Android back / iOS swipe-back).

  Requires: -i <instance> or --uri <ws-uri>

  Example:
    marionette -i my-app press-back-button

  Output (stdout):
    Back button pressed, route was popped

  Output if on root route (stdout):
    Back button pressed, no route to pop (app may exit)

  Notes:
    - Works with Navigator, GoRouter, and other routing solutions.
    - If the app is on the root route, the system may minimize or close the
      app (same as real back button behavior on Android).
    - Respects PopScope / WillPopScope widgets.

---

### swipe

Swipe/drag on the app. Useful for PageView, Dismissible, Drawer, and Slider.
Use either element-based mode (matcher + direction) or coordinate-based mode.

  Requires: -i <instance> or --uri <ws-uri>

  Element-based options:
    --key <string>        Match by ValueKey<String> (most reliable)
    --identifier <string> Match by Semantics identifier (stable alternative)
    --text <string>       Match by visible text content
    --type <string>       Match by widget type name (e.g., PageView)
    --direction <dir>     left, right, up, or down (required for this mode)
    --distance <number>   Swipe distance in pixels (default: 200)
    --start-x <number>    Optional finger start X (requires --start-y)
    --start-y <number>    Optional finger start Y (requires --start-x)

  Coordinate-based options (all required together):
    --start-x <number>    Start X coordinate
    --start-y <number>    Start Y coordinate
    --end-x <number>      End X coordinate
    --end-y <number>      End Y coordinate

  Examples:
    marionette -i my-app swipe --type PageView --direction left
    marionette -i my-app swipe --key carousel --direction right --distance 300
    marionette -i my-app swipe --text Notes --direction up --start-x 200 --start-y 800
    marionette -i my-app swipe --start-x 300 --start-y 400 --end-x 50 --end-y 400

  Output (stdout):
    Swiped left on element matching: {type: PageView}
    Swiped from (300.0, 400.0) to (50.0, 400.0)

---

### scroll-to

Scroll until an element becomes visible.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    --key <string>        Match by ValueKey<String>
    --identifier <string> Match by Semantics identifier
    --text <string>       Match by visible text content

  Example:
    marionette -i my-app scroll-to --text "Bottom Item"

  Output (stdout):
    Scrolled to element matching {text: Bottom Item}

---

### take-screenshots

Capture screenshots and save to PNG files.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    -o, --output <path>   Output file path (mandatory)
    --open                Open the file after saving

  Example:
    marionette -i my-app take-screenshots --output ./screenshot.png

  Output (stdout):
    Saved screenshot: ./screenshot.png

  Multi-view apps produce numbered files:
    Saved screenshot: ./screenshot.png
    Saved screenshot: ./screenshot_1.png

---

### record-video

Record a video of the running Flutter app and save to a WebM file.
Requires ffmpeg to be installed.

  Requires: -i <instance> or --uri <ws-uri>

  Options:
    -o, --output <path>       Output file path (mandatory, must end with .webm)
    -d, --duration <seconds>  Recording duration — records until Ctrl+C if not set
    --width <pixels>          Video width in pixels
    --height <pixels>         Video height in pixels
    --open                    Open the video after recording
    --ffmpeg-path <path>      Path to ffmpeg binary (default: ffmpeg)
    -v, --verbose             Print diagnostic details (probe response, frame counts)
    --transport <mode>        Frame transport: auto (default), tcp, ws
                              auto: try TCP, fall back to reverse-WS via adb
                              tcp:  force TCP (fail if unreachable)
                              ws:   force reverse-WS (requires adb)
    --frame-port <port>       Use a specific TCP port for frame streaming instead
                              of auto-negotiation (mutually exclusive with --transport ws)

  Examples:
    marionette -i my-app record-video --output ./recording.webm
    marionette -i my-app record-video -o ./demo.webm -d 10
    marionette --uri ws://127.0.0.1:8181/ws record-video -o ./recording.webm --width 1280 --height 720
    marionette -i my-app record-video -o ./demo.webm --transport ws

  Output (stdout):
    Starting screencast...
    Recording 640x480 video to ./recording.webm...
    Press Ctrl+C to stop recording.
    Recording complete: ./recording.webm (10s, 250 frames)

  Prerequisites:
    ffmpeg must be installed and on PATH (or specify --ffmpeg-path).
      macOS:   brew install ffmpeg
      Ubuntu:  sudo apt install ffmpeg
      Windows: winget install ffmpeg

  Exit codes: 0 success, 1 ffmpeg not found or recording failed, 64 invalid options

---

### get-logs

Retrieve collected application logs.

  Requires: -i <instance> or --uri <ws-uri>

  Example:
    marionette -i my-app get-logs

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

### hot-restart

Perform a hot restart of the Flutter app. Fully restarts the app from main()
and resets all state. Use it for changes a hot reload cannot pick up (e.g.
main()/bootstrap edits, global singletons, or state shape). Requires the app
to be running via `flutter run`.

  Requires: -i <instance> or --uri <ws-uri>

  Example:
    marionette -i my-app hot-restart

  Output (stdout, exit 0):
    Hot restart completed successfully.

  Output on failure (stderr, exit 1):
    Hot restart failed or is unavailable. Make sure the app is running via `flutter run`.

---

### doctor

Check connectivity of all registered instances, then the native lane: adb
and devices, the UIAutomator2 APKs (cache checksum), booted iOS Simulators,
the WebDriverAgent build and port 8100 (macOS), orphaned device servers and
native sessions.

  Example:
    marionette doctor

  Output (stdout):
    Checking 2 instance(s)...

      my-app (ws://127.0.0.1:8181/ws) ... OK
      other-app (ws://127.0.0.1:9090/ws) ... FAILED

    Some instances are unreachable. Use "marionette unregister <name>" to remove stale entries.

    Native lane:
      ✓ Android Debug Bridge version 1.0.41
      ✓ Android device emulator-5554
      ! No iOS Simulator is booted.
          Fix: Run "open -a Simulator" or "xcrun simctl boot <udid>".
      ✗ Orphaned WebDriverAgent (pid 4242): no native session or process owns it; it can block the port of a new session.
          Fix: kill 4242

  ✓ works, ! not set up (matters only for that platform), ✗ problem.

  Exit codes: 0 all reachable and no problem, 1 otherwise

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

## Native lane (system UI outside Flutter)

Flutter commands only see the app's widget tree. Permission dialogs, system
alerts, share sheets, pickers, notifications, browser sign-in, biometric
prompts, native screens and WebView content are only reachable through the
native-* commands (UIAutomator2 on Android, WebDriverAgent on an iOS
Simulator). While system UI covers the app, get-interactive-elements still
lists the Flutter widgets underneath as if they were reachable — check
native-get-elements when an action has no effect.

### Workflow

1. `marionette native-connect --platform android [--serial <serial>]`
   or `marionette native-connect --platform ios [--udid <udid>]`.
   Starts the device-side server once (the first Android start downloads
   it; iOS needs a prebuilt WebDriverAgent — see `marionette doctor`). The
   server keeps running between commands.
2. Run native-* commands. They reuse the session; no per-command setup.
3. `marionette native-disconnect` when done (stops the server it started).

Several devices at once: give each a name with
`--native-session <name>` (before the command), e.g.
`marionette --native-session iphone native-tap --text Allow`.
Prefer one client per Android device at a time: UIAutomator2 has a single
session, so an MCP server and a CLI session on the same device take it from
each other — both recover, but an action in flight can be interrupted
(native-connect warns when it reuses another process's server).

### Selectors and coordinates

Element commands take a selector: `--text` (exact; `--label` in
native-enter-text), `--text-contains`, `--id` (Android resource id / iOS
accessibility identifier), `--type`, `--index`. All given options must
match. If several elements match and only one is tappable, that one is
used; otherwise the command fails and lists the candidates — add --index
or a more specific option. Coordinates (--x/--y, --start-x …) are
screenshot pixels, the pixel grid of native-take-screenshot, on both
platforms — never Flutter logical pixels (use native-map-flutter-rect).

### Session commands

  native-connect --platform android|ios [--serial S] [--udid U]
      Start or reuse the server and save the session. Exit 1 with the
      reason and a hint when the device or server is not available.
  native-sessions
      List sessions: name, platform, device, URL, running / not running.
  native-disconnect
      Delete the session; stop the server if native-connect started it.

### Commands (each mirrors the MCP tool native_<name>)

  native-get-elements [selector without --index] [--clickable-only]
                      [--no-include-foreground-app]
      JSON {"elements": [...], "foregroundApp": "..."}; each element has
      type, text, id, bounds {x, y, width, height} (screenshot pixels),
      clickable, and state when informative: value (typed content),
      enabled, focused, checked, selected, scrollable.
  native-wait-for [selector without --index] [--state visible|gone]
                  [--timeout-ms 10000] [--interval-ms 500]
      Prints the element (visible) or the elapsed time (gone); exit 1 on
      timeout, naming the foreground app. Wait for an element of the
      expected screen, not for a package name (not element text; see
      foregroundApp of native-get-elements).
  native-tap <selector> | --x X --y Y
  native-double-tap <selector> | --x X --y Y [--delay-ms 100]
  native-long-press <selector> | --x X --y Y [--duration-ms 600]
  native-pinch --scale S [<selector> | --x X --y Y] [--duration-ms D]
      S > 1 zooms in, < 1 out (0.1–10).
  native-swipe --start-x --start-y --end-x --end-y [--duration-ms 300]
      iOS back gesture: start at x=1. It does not wait for the content to
      settle — on iOS a tap right after a fling only stops the scrolling;
      use native-wait-for (or native-scroll, which settles) before tapping.
  native-scroll --direction up|down|left|right [target selector]
                [--within-text|--within-text-contains|--within-id|
                 --within-type|--within-index] [--max-swipes 10]
                [--distance D] [--start-x X --start-y Y]
      Direction is the finger's. With a target, swipes until it is visible
      and stops at the end of the list; --within-* swipes inside that
      container (nested lists, pickers).
  native-enter-text --text T [--label|--text-contains|--id|--type|--index]
                    [--clear]
      Appends; without a selector types into the focused field (also
      Flutter fields on Android).
  native-press-key --key back|home|enter|backspace|tab|recents|volume_up|
                         volume_down
      back, recents, tab: Android only.
  native-hide-keyboard
  native-take-screenshot --output file.png [selector]
  native-device-info
      JSON: platform, OS, model, screen, orientation, foreground app,
      default app id.
  native-permissions --action grant|revoke|reset --permission camera|
      microphone|photos|location|contacts|calendar|notifications|all
      [--app-id ID]
      Without the system dialog; reset makes the app ask again. Revoking
      may terminate the app (the output says so).
  native-open-url --url URL
      Web page or deep link. iOS may ask "Open in …?": native-tap --text Open.
  native-app --action activate|background|terminate|restart [--app-id ID]
      On Android terminate / restart also remove the app's notifications.
  native-notifications --action open|close|push [--title T] [--body B]
                       [--payload JSON] [--app-id ID]
      push: iOS Simulator; background the app a few seconds first.
  native-set-orientation --orientation portrait|landscape
  native-set-location --latitude LAT --longitude LON
  native-biometrics --action match|nonMatch|enroll|unenroll
      Answers a Face ID / Touch ID / fingerprint prompt on an emulator or
      simulator; enroll / unenroll: iOS Simulator only.
  native-map-flutter-rect --x X --y Y [--width W] [--height H]
      With -i <instance> or --uri: converts Flutter bounds (from
      get-interactive-elements) to screenshot pixels for a native gesture
      on a platform view (camera preview, map, video).

  --app-id defaults to the app under test: the first non-system app seen in
  front in this session.

  Messages and hints are shared with the MCP tools: an argument named in
  camelCase (maxSwipes, timeoutMs, appId, action=close) is the option in
  kebab case (--max-swipes, --timeout-ms, --app-id, --action close).

  Examples:
    marionette native-connect --platform android
    marionette native-wait-for --text Allow --timeout-ms 5000
    marionette native-tap --text Allow
    marionette native-enter-text --label "User name" --text "Jan"
    marionette native-scroll --direction up --within-id "File View" \
        --text marionette_file_37.txt
    marionette -i my-app native-map-flutter-rect --x 24 --y 300 \
        --width 340 --height 200

### Platform notes

- iOS Notification Center: a tap on a notification does nothing; swipe it
  right with native-swipe. A collapsed "N Notifications" button must be
  tapped first. Opened over the app it is not in the tree — background the
  app first. A banner can be tapped.
- Android: toasts and heads-up banners are visible only on screenshots on
  recent versions (older ones list toasts read-only); a tree read during a
  toast waits until it is gone.
- Android with a hardware keyboard shows Gboard's floating toolbar:
  native-hide-keyboard refuses (Back would close the screen).
- Android: after native-app --action activate / restart, wait for the app's
  first screen (native-wait-for) before native-open-url — a deep link sent
  while the app starts is lost.
- get-interactive-elements warns when the app is not in front (system UI or
  another screen covers it). On iOS an alert or sheet shown by the app
  itself gives no warning — if a Flutter action has no effect, check
  native-get-elements.
- native-tap, native-enter-text and the gestures refuse a disabled element
  (enabled: false). On iOS the app's elements stay listed, disabled, under
  a system sheet or picker — act on the sheet or close it first.
- A focused Flutter text field on iOS shows its hint as a second line of
  its label; --label matches the first line, --text of
  native-get-elements needs the whole text (use --text-contains).

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
- --identifier (Semantics identifier) is an equally stable alternative to --key
  when a widget has no ValueKey but does set an accessibility identifier
- Run `get-interactive-elements` first to discover what's on screen before interacting
- Instance names are alphanumeric with hyphens/underscores: [a-zA-Z0-9_-]+
- Flutter commands are stateless — each opens a fresh connection, so no session management needed
- native-* commands share a session started by native-connect; run native-disconnect at the end
''';
