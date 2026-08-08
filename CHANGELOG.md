# Unreleased

- Add `set_device_config` tool and `set-device-config` CLI command for overriding text scale, bold text, platform brightness, and reduced motion in a running app — opt in by wrapping your root widget in the new `MarionetteDeviceConfig`

- Fix extension errors being reported as the generic `Server error` instead of the detail the extension returned — this silently swallowed every validation message and setup instruction, including the `get_logs` log-collector onboarding help

# 0.6.0

- Promote schema-bearing custom extensions to first-class MCP tools via the new `ExtensionInputSchema`/`ExtensionParam` DSL
- Add `press_key` tool for dispatching hardware key events with modifiers
- Add `hot_restart` tool for fully restarting the app from `main()`
- Add `secondary_tap` tool for right mouse button clicks on desktop
- Add `swipe` CLI command for element- and coordinate-based swipe/drag gestures
- Surface `Semantics(label:)` and `Semantics(value:)` in `get_interactive_elements`
- Exit the stdio MCP server on stdin EOF to prevent orphaned processes
- Bump `mcp_dart` to `^2.1.0` and drop the bespoke Copilot-compat stdio transport
- Add a `Dockerfile` for building `marionette_mcp` as a container image

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
