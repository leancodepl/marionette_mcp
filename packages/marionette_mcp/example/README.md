# Marionette counter example

This Flutter counter app initializes `MarionetteBinding` so an MCP client can
inspect the UI, tap the increment button, and capture screenshots.

Use the Flutter version pinned in the repository's [`.fvmrc`](https://github.com/leancodepl/marionette_mcp/blob/main/.fvmrc).
This example includes the MCP server as a dev dependency. Its combined graph
cannot resolve on Flutter 3.27 because `flutter_test` and `mcp_dart` 2.4.3
require incompatible `meta` versions. Flutter 3.27 apps using the binding with
a separately installed server remain supported.

Clone the repository to include the sibling packages this example depends on:

```bash
git clone https://github.com/leancodepl/marionette_mcp.git
cd marionette_mcp/packages/marionette_mcp/example
flutter pub get
flutter run
```

Configure your MCP client to start `dart run marionette_mcp` from this directory.
Pass the VM service URI printed by `flutter run` to `connect`, then use
`get_interactive_elements` to discover the increment control before tapping it.

For custom widgets, log collection, and session reports, use the richer
[repository example](https://github.com/leancodepl/marionette_mcp/tree/main/example). See the
[architecture guide](https://github.com/leancodepl/marionette_mcp/blob/main/docs/architecture.md) for the server's structure
and extension points.
