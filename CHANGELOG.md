# Unreleased

# 0.6.0

- Promote schema-bearing custom extensions to first-class MCP tools. Registering an extension with an `inputSchema` (declared via the new typed `ExtensionInputSchema`/`ExtensionParam` DSL) now surfaces it as an individually-named, discoverable tool with a validated input schema — the agent gets argument hints and enum autocomplete, invalid arguments are rejected before reaching your app, and declared defaults are applied before the callback runs. Promoted tool names are sanitized for strict clients (e.g. VS Code Copilot's `[a-z0-9_-]`-only rule) while the extension is still invoked by its real name. Schema-less extensions stay supported through the generic `call_custom_extension` tool.
- Add the `press_key` tool (plus the `press-key` CLI command) for dispatching real hardware key events to the focused element — named keys (`enter`, `tab`, `escape`, arrows, etc.) and single characters, with optional control/shift/alt/meta modifiers. Unlike `enter_text`, which rewrites a field's value, this drives form submission, focus traversal, dismiss, and app shortcuts.
- Add the `hot_restart` tool (plus the `hot-restart` CLI command), mirroring hot reload but fully restarting the app from `main()` and resetting all state. Requires the app to be launched via `flutter run`; the connector re-resolves the new root isolate and re-registers its extensions after the restart.
- Add a `swipe` CLI command, wiring the existing swipe/drag gesture into the CLI in both element-based (`--key`/`--text`/`--type` + `--direction`) and coordinate-based (`--start-x`/`--start-y`/`--end-x`/`--end-y`) modes.
- Add the `secondary_tap` tool (plus the `secondary-tap` CLI command) for right mouse button clicks on desktop. It dispatches a mouse pointer with the secondary button pressed, triggering Flutter's `onSecondaryTap` (e.g. context menus). Touch `tap` is unchanged.
- Surface `Semantics(label:)` and `Semantics(value:)` in `get_interactive_elements`. Widgets that render via inline-span trees (`Text.rich`, custom-painted text, etc.) where `toPlainText()` loses structure can now be made fully readable by agents through an explicit accessibility annotation, without altering the rendered widget.
- Bump the `mcp_dart` dependency to `^2.1.0`.
- Exit the stdio MCP server when its stdin reaches EOF (e.g. the MCP host crashes or disconnects without sending a signal), preventing orphaned `marionette_mcp` processes from accumulating. Removed the bespoke Copilot-compat stdio transport in favour of `mcp_dart`'s built-in `StdioServerTransport` — `mcp_dart` 2.1.0 parses GitHub Copilot's object-typed `tasks` capabilities natively, so the workaround is no longer needed.
- Add a `Dockerfile` so `marionette_mcp` can be built as a container image and submitted to the Docker MCP Registry; the image installs the published package from pub.dev and runs the server over stdio.

# 0.5.0

- **Breaking:** Pass `Element` instead of `Widget` to the `extractText` configuration callback, giving access to the full element context. Migration: change `(widget)` to `(element)` and use `element.widget` to access the widget.
- Add gesture support across all layers: `swipe/drag`, `long_press`, `double_tap`, `pinch_zoom`, and `press_back_button`.
- Add video recording with TCP/WS transport and Android auto-fallback.
- Improve screencast stability with broken-pipe race handling, concurrent stop safety, and orphaned session cleanup.
- Improve runtime robustness around input validation, resource cleanup, and non-monotonic timestamp handling.
- Strengthen release CI with explicit minimum-version compatibility checks and Flutter version sourced from `.fvmrc`.

# 0.4.0

- Add `marionette_cli` package with multi-instance CLI support
- Add `call_custom_extension` tool for arbitrary VM service extensions
- Add custom extension registry with `registerMarionetteExtension`
- Add focused selector to `enter_text`
- Add version compatibility check on connect
- Decouple logging from `marionette_flutter` into `marionette_logger` and `marionette_logging`
- Improve `ScrollSimulator` with reverse scrolling direction and configurable max scroll attempts
- Fix tap matching widgets behind modal route barriers
- Fix `onChanged` not being called on `enter_text`
- Fix pointer device collision with macOS mouse cursor
- Fix extracted text not being exposed in interactive elements
- Ensure correct status code range in `MarionetteExtensionError`

# 0.3.0

- Add screenshot resizing configuration
- Fix SIGTERM handling on Windows
- Add GitHub Copilot support
- Require Dart 3.10 for the MCP server
- Fix `hot_reload` tool response handling

# 0.2.4

- Add CI workflow with analyze, format, and version checks
- Add version generation script with validation and robustness
- Replace example symlinks with actual directories in both packages
- Improve project structure and dependencies

# 0.2.3

- Add example symlinks for improved pub.dev package scoring
- Fix documentation lints for angle brackets in code references

# 0.2.2

- Add compatibility for Copilot `initialize` call
- Make configuration parameter optional in `MarionetteBinding.ensureInitialized()`

# 0.2.1

- Update README

# 0.2.0

- Support tapping by widget type
- Support tapping by coordinates
- Return more info in `get_interactive_elements`
- Add hot reload tool, and return logs only since last hot reload
- `get_interactive_elements` returns only hittable elements now
- The tools have better naming to conform to the MCP implementations
- `scroll_to` does not assume that the widget is in the tree
- `Text` is a stopwidget now

# 0.1.0

- Initial version of Marionette MCP
- Support for getting the interactive widget tree
- Support for entering text
- Support for tapping and scrolling
- Support for getting logs from `logging` package
