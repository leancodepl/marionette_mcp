# AGENTS.md

## Cursor Cloud specific instructions

This is a Dart/Flutter monorepo using Dart workspaces (`workspace:` in root `pubspec.yaml`). No Docker, databases, or external services are required.

### SDK

- Flutter SDK (stable channel) is installed at `/opt/flutter` and added to `PATH` via `~/.bashrc`.
- Dart SDK ships bundled with Flutter at `/opt/flutter/bin/cache/dart-sdk/bin`.
- The project uses FVM (`.fvmrc` → `"stable"`), but we install Flutter directly instead of via FVM in the cloud environment.

### Dependencies

Run `flutter pub get` from the workspace root (`/workspace`). This resolves all packages in the workspace including nested examples. Do **not** use `dart pub get` at root — it fails because the workspace includes Flutter packages.

### Lint / Analyze

CI runs analysis per-package (see `.github/workflows/ci.yaml`). Key commands:

```
cd packages/marionette_mcp && dart analyze --fatal-infos lib bin
cd packages/marionette_cli && dart analyze --fatal-infos lib bin
cd packages/marionette_flutter && flutter analyze --fatal-infos lib
cd packages/marionette_logger && flutter analyze --fatal-infos lib
cd packages/marionette_logging && flutter analyze --fatal-infos lib
```

### Format

```
cd packages/marionette_mcp && dart format --set-exit-if-changed lib bin
cd packages/marionette_cli && dart format --set-exit-if-changed lib bin
cd packages/marionette_flutter && dart format --set-exit-if-changed lib
cd packages/marionette_logger && dart format --set-exit-if-changed lib
cd packages/marionette_logging && dart format --set-exit-if-changed lib
cd tool && dart format --set-exit-if-changed .
```

### Tests

```
cd packages/marionette_mcp && dart test
cd packages/marionette_cli && dart test
cd packages/marionette_flutter && flutter test
```

### Running the MCP server

- **Stdio mode** (default): `dart run packages/marionette_mcp/bin/marionette_mcp.dart`
- **SSE mode**: `dart run packages/marionette_mcp/bin/marionette_mcp.dart --sse-port 3000`
- **CLI**: `dart run packages/marionette_cli/bin/marionette.dart --help`

### Gotchas

- The version file `packages/marionette_mcp/lib/src/version.g.dart` is generated. If it gets out of sync, regenerate with `dart tool/generate_version.dart`.
- CI does NOT run tests — only analysis and formatting. But tests exist and should be run during development.
- `marionette_flutter`, `marionette_logging`, and `marionette_logger` are Flutter packages — use `flutter` commands (not `dart`) for `pub get`, `test`, and `analyze`.
