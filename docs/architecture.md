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
    server_context.dart        shared connection/session state and ownership
    server_runner.dart         logging, transport startup, and shutdown
    step_logging.dart          MCP result/session logging adapter
    tools/
      base_tool.dart           metadata and execute contract
      tools.dart               createAllTools and registration
      connection_tools.dart    connect/disconnect contracts and lifecycle calls
      dynamic_extension_tools.dart  app-defined typed tools and registrations
      *_tools.dart             tools grouped by responsibility
  lib/src/                     runtime implementation details
```

Each static tool extends `BaseTool` and receives its connector and logger
through its constructor. Screenshot tools also receive the session step
logger. `createAllTools` composes all 20 built-in tools, including connection
tools, without opening sockets or starting a process. `createMcpServer` uses
`registerMcpTools` to register them and apply step logging once, at the
composition boundary. The context contains no tool definitions or registration
loop. Connection tools own their additional
session-report transitions; app-defined tools are discovered dynamically.
In-flight tool calls retain their original report session; a superseded
connection attempt cannot add a step to its replacement's report.

## Public package boundaries

CLI adapters import `package:marionette_mcp/runtime.dart` for app connections,
selectors, reports, and recording. They import
`package:marionette_mcp/marionette_mcp.dart` for server startup. Other packages
should use these entrypoints rather than importing `lib/src` files. Existing
MCP tools and executable options keep their names and input schemas.
Shared report formatting and persistence live in `src/session/report_steps.dart`
without an MCP dependency; MCP result interpretation lives in `mcp/step_logging.dart`.
Former internal MCP paths are compatibility exports of the new implementations.

## Structured tool results

Every built-in tool advertises an `outputSchema` and returns matching
`structuredContent` on success. The SDK validates these results. Existing
human-readable text and inline images remain available in `content`; error
results retain `isError: true` and need not match a success schema.

| Tool family | Structured success data |
| --- | --- |
| Actions, keyboard, device config, reload/restart | `message`; back navigation may also include `didPop` |
| UI inspection | `elements`, `count` |
| Logs | `logs`, `count` |
| Screenshots | `count`, `inline`, and saved `paths` when applicable; image bytes stay in `content` |
| Extension discovery | `extensions`, `count` |
| Generic and dynamically promoted extensions | `response`, an object containing the app's result |
| Connect | `uri`, `sessionReportsEnabled`, optional `sessionPath` or nonfatal `warning` |
| Disconnect | `disconnected`, optional closing `sessionPath` |

Extension output fields are app-defined, so their response envelope permits
arbitrary properties rather than claiming a schema the app has not supplied.

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
APIs under legacy initialization and stateless discovery, including successful
structured results, dynamic extension removal, and ordinary error results.
Its catalog fixture
was captured from the original 0.7.0 implementation with SDK 2.4.3; update it
only for an intentional tool-contract change. The comparison permits the new
output schemas while preserving every original input contract and annotation.
Shutdown regressions use a real
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
