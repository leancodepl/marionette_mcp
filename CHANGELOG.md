# 0.5.0
- **Breaking:** Pass `Element` instead of `Widget` to the `extractText` configuration callback, giving access to the full element context. Migration: change `(widget)` to `(element)` and use `element.widget` to access the widget.

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
