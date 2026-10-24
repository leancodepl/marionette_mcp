# Server and runtime architecture

The MCP server follows the `mcp_dart` CLI template's separation of server
composition, configuration, and typed tools:

```text
packages/marionette_mcp/
  bin/marionette_mcp.dart       parse options and start the server
  lib/marionette_mcp.dart       public server API
  lib/runtime.dart             public app/session/recording runtime API
  lib/mcp/
    mcp.dart                   createMcpServer and server instructions
    server_config.dart         options shared with marionette mcp
    server_context.dart        app connection and session lifecycle
    tools/
      base_tool.dart           metadata and execute contract
      tools.dart               createAllTools and registration
      *_tools.dart             tools grouped by responsibility
  lib/src/                     runtime implementation details
```

Each static tool extends `BaseTool` and receives its connector and logger
through its constructor. Screenshot tools also receive the session step
logger. `createAllTools` composes these tools without opening sockets or
starting a process. `createMcpServer` registers them and applies step logging
once, at the composition boundary. Connection tools own their additional
session-report transitions; app-defined tools are discovered dynamically.
In-flight tool calls retain their original report session; a superseded
connection attempt cannot add a step to its replacement's report.

## Public package boundaries

CLI adapters import `package:marionette_mcp/runtime.dart` for app connections,
selectors, reports, and recording. They import
`package:marionette_mcp/marionette_mcp.dart` for server startup. Other packages
should use these entrypoints rather than importing `lib/src` files. Existing
MCP tools and executable options keep their names and wire schemas.

For embedding, `createMcpServer(context: context)` accepts an explicitly owned
`VmServiceContext`. The caller must await `context.dispose()` and
`server.close()` when its transport ends. The standard `runMcpServer` entrypoint
performs both operations on EOF, signals, and transport startup failure.
Disposing the context retires dynamic tools and closes its app connection.
Disconnecting releases dynamic tool names, so reconnecting uses the current
app's schemas without retaining disabled registrations.

Recording setup owns its WebSocket listener until a `RecordingSession` has
been created successfully. Startup failure closes the listener; after a
successful transfer the session owns cleanup.

## CLI selection

CLI coordinate selectors require both `--x` and `--y`, with finite numeric
values. Coordinate swipes require all four start/end coordinates. Malformed
coordinates fail before invoking the app instead of silently dropping a value.
Coordinate, element, and focused targeting are separate modes; an element
mode may retain combined key, identifier, text, and type filters. Ancestor
scope keeps its existing behavior, including being ignored by coordinate and
focused targeting.

## Verification

From the workspace root, resolve dependencies with `flutter pub get`. Run
`dart analyze lib bin test` and `dart test` in both `packages/marionette_mcp`
and `packages/marionette_cli`, then `flutter test --no-pub` in
`packages/marionette_flutter`.

`server_api_test.dart` drives the real executable through public SDK client
APIs under legacy initialization and stateless discovery. Its catalog fixture
was captured from the original 0.7.0 implementation with SDK 2.4.3; update it
only for an intentional tool-contract change. Shutdown regressions use a real
Dart VM service fixture and cover connected EOF and signals.

`dart tool/check_frame_protocol.dart` checks Flutter-encoded frames against
the MCP consumer, including fragmented delivery. CI runs this check on both
the normal and minimum supported toolchains. This keeps the production
packages independent while detecting drift in their shared wire format.

The minimum-toolchain CI job selects separate workspace groups for the
standalone Dart server/CLI and the Flutter binding/adapters. Flutter 3.27's
`flutter_test` pins `meta` to 1.15, while `mcp_dart` 2.4.3 requires 1.16 or
newer. Temporary `pubspec_overrides.yaml` files select workspace members only;
they never override dependency constraints. Dart checks use `--no-example` to
avoid resolving Flutter examples in the server-only workspace. The normal
CI job continues to validate the complete workspace on the pinned Flutter SDK.
The complete workspace and the MCP package's Flutter example combine both
dependency graphs and therefore require a newer Flutter SDK. Flutter 3.27 is
supported for apps using the binding with the server running separately.
