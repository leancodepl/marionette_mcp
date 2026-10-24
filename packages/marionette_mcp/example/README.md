# Marionette counter example

This Flutter counter app initializes `MarionetteBinding` so an MCP client can
inspect the UI, tap the increment button, and capture screenshots.

Use the Flutter version pinned in the repository's [`.fvmrc`](../../../.fvmrc).
This example includes the MCP server as a dev dependency. Its combined graph
cannot resolve on Flutter 3.27 because `flutter_test` and `mcp_dart` 2.4.3
require incompatible `meta` versions. Flutter 3.27 apps using the binding with
a separately installed server remain supported.

From the repository root:

```bash
cd packages/marionette_mcp/example
flutter pub get
flutter run
```

Configure your MCP client to start `dart run marionette_mcp` from this directory.
Pass the VM service URI printed by `flutter run` to `connect`, then use
`get_interactive_elements` to discover the increment control before tapping it.

For custom widgets, log collection, and session reports, use the richer
[repository example](../../../example/). See the
[architecture guide](../../../docs/architecture.md) for the server's structure
and extension points.
