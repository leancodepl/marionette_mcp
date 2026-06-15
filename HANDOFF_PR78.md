# Handoff — PR #78 "Dynamic extension tools": testing + fix the arg-coercion (types) issue

> Target branch for this work: `feat/dynamic-extension-tools` (PR #78).
> Audience: a local Claude Code environment **with the Dart + Flutter SDK installed**
> (the cloud env that wrote this had no toolchain, so nothing below was executed there —
> all claims are from source reading and must be re-verified locally).

---

## 1. Background (what PR #78 does)

`marionette_mcp` is an MCP server that drives a running Flutter app over the Dart VM
service. Flutter apps can register **custom extensions** via
`registerMarionetteExtension(...)`. Before this PR they were reachable only through one
generic catch-all MCP tool, `call_custom_extension`.

PR #78 lets an extension declare a **typed input schema**; when it does, the MCP server
**promotes it to a first-class, individually-registered MCP tool** (own name, description,
validated input schema). Schema-less extensions still work via `call_custom_extension`.

Key files:
- `packages/marionette_flutter/lib/src/binding/extension_schema.dart` — author-facing
  schema DSL (`ExtensionInputSchema` / sealed `ExtensionParam`: `.string/.integer/.number/.boolean`).
- `packages/marionette_flutter/lib/src/binding/register_extension.dart` — `inputSchema` param.
- `packages/marionette_mcp/lib/src/vm_service/dynamic_extension_tools.dart` — discovery +
  dynamic `registerTool`, reconnect "revival", and `coerceToStringMap`.
- `packages/marionette_mcp/lib/src/vm_service/tools/extension_tools.dart` — the legacy
  `list_custom_extensions` / `call_custom_extension` tools.
- `packages/marionette_mcp/lib/src/vm_service/vm_service_context.dart` — lifecycle wiring
  (register on connect, disable on disconnect).

### Why the schema is restricted to flat scalars (important context for the fix)
Custom extension params travel over the VM service as a flat `Map<String, String>` — the
`dart:developer` handler signature is `(String method, Map<String, String> parameters)`.
The VM's `vmservice` layer force-stringifies every param value before delivering it
(`sdk/lib/vmservice/message.dart` → `_convertAllToStringInPlace` calls `.toString()` on
each value for any non-allowlisted method, which includes all `ext.flutter.*` extensions).

Consequence (verified from SDK source, **re-verify locally**):
- Scalars round-trip fine: `3 → "3"`, `true → "true"`, `1.5 → "1.5"`.
- **Non-scalars are corrupted**: a Dart `Map`/`List` is stringified with Dart's
  `toString()`, e.g. `{min: 1}` (NOT JSON `{"min":1}`) and `[a, b]` — un-`json.decode`-able.

That is exactly why `ExtensionParam` is scalar-only at the type level.

---

## 2. Environment setup

Repo is a **Dart pub workspace** (no melos). Root `pubspec.yaml` lists members; SDK `^3.6.0`.

```bash
# from repo root
git checkout feat/dynamic-extension-tools
git pull origin feat/dynamic-extension-tools

# resolve deps (workspace resolves all members)
dart pub get

# Flutter is required for marionette_flutter / example
flutter --version    # confirm Flutter SDK present
```

If individual packages need their own resolve:
```bash
cd packages/marionette_mcp     && dart pub get
cd packages/marionette_flutter && flutter pub get
```

---

## 3. Run the existing test suite (do this FIRST, establish a green baseline)

Mirror CI (`.github/workflows/ci.yaml`):

```bash
# marionette_mcp (pure Dart)
cd packages/marionette_mcp
dart analyze --fatal-infos lib bin
dart format --set-exit-if-changed lib bin
dart test

# marionette_flutter (Flutter)
cd ../marionette_flutter
flutter analyze --fatal-infos lib
dart format --set-exit-if-changed lib
flutter test
```

PR-specific tests that must pass:
- `packages/marionette_flutter/test/extension_schema_test.dart`
- `packages/marionette_flutter/test/register_extension_test.dart`
- `packages/marionette_mcp/test/vm_service/dynamic_extension_tools_test.dart`

Also regenerate/verify the version stamp (CI checks it):
```bash
dart tool/generate_version.dart
git diff --exit-code packages/marionette_mcp/lib/src/version.g.dart
```

---

## 4. THE TYPES ISSUE TO FIX

### Symptom / root cause
The new dynamic-tool path coerces args **in the server** before sending, using
`coerceToStringMap` (`dynamic_extension_tools.dart`):
- scalars → `.toString()`, `null → ""`, **nested → `jsonEncode`** (valid JSON).

The legacy `call_custom_extension` tool does **NOT** coerce. In
`packages/marionette_mcp/lib/src/vm_service/tools/extension_tools.dart` (callback around
lines 98–114) it does:

```dart
final extensionArgs =
    (args['args'] as Map<String, dynamic>?) ?? <String, dynamic>{};
...
final response = await connector.callCustomExtension(extensionName, extensionArgs);
```

It passes raw values through and relies on the VM's `.toString()` fallback. Result: the two
code paths behave **inconsistently**, and the escape hatch **silently corrupts nested
object/array args** (Dart `toString()` instead of JSON). Scalars happen to work, so it's a
latent correctness bug, not a crash.

### Fix (recommended)
Route `call_custom_extension` through the **same** coercion so behavior is identical to the
typed path and non-scalars become valid JSON.

`coerceToStringMap` is already public (exported from `dynamic_extension_tools.dart`,
declared "Public for testing"). Two options:

**Option A (minimal):** import and reuse it in `extension_tools.dart`.
```dart
import 'package:marionette_mcp/src/vm_service/dynamic_extension_tools.dart'
    show coerceToStringMap;
...
final extensionArgs = coerceToStringMap(
  (args['args'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
);
```

**Option B (cleaner, preferred for layering):** extract `coerceToStringMap` /
`_coerceToStringMap` into a shared helper (e.g.
`packages/marionette_mcp/lib/src/vm_service/tools/arg_coercion.dart`), and import it from
**both** `dynamic_extension_tools.dart` and `extension_tools.dart`. This avoids a
tool-file depending on the dynamic-tools file.

Pick B if it doesn't balloon the diff; otherwise A is acceptable. Either way the behavior
contract becomes: **the server always produces the final `Map<String,String>`; the VM's
`.toString()` becomes a no-op on already-stringified values.**

### Why this is safe (no behavior regression for existing users)
- String args: unchanged (pass through).
- Number/bool args: `"3"` / `"true"` — same string the VM would have produced anyway.
- Nested args: change from corrupted Dart `toString()` to valid `jsonEncode` — strictly an
  improvement; nothing previously relied on the broken form.

### Tests to add/extend
- Add a unit test for the `call_custom_extension` callback asserting that nested args are
  `jsonEncode`d and scalars stringified (mirror the existing `coerceToStringMap` group in
  `dynamic_extension_tools_test.dart`). If there is no `extension_tools_test.dart`, create
  `packages/marionette_mcp/test/vm_service/tools/extension_tools_test.dart` with a fake
  `VmServiceConnector` capturing the args passed to `callCustomExtension`.
- If you take Option B, move/extend the existing `coerceToStringMap` tests to the new file.

### Acceptance criteria for the fix
- [ ] `call_custom_extension` and the dynamic tools produce identical wire args for the
      same input.
- [ ] Nested object/array args sent via `call_custom_extension` arrive as valid JSON
      strings (verified by a unit test on the captured connector args).
- [ ] `dart analyze --fatal-infos`, `dart format`, and `dart test` all green in
      `packages/marionette_mcp`.
- [ ] No change to `marionette_flutter` public API required.

---

## 5. Manual / end-to-end verification (needs a running app)

The example app already defines a schema-bearing `appNavigation.goToPage` (enum of pages)
and a schema-less `appNavigation.getPageInfo`.

1. `cd example && flutter run` (debug). Note the VM service URI (`ws://127.0.0.1:.../ws`).
2. Point an MCP client at **this branch's** `marionette_mcp`
   (`cd packages/marionette_mcp && dart run marionette_mcp`) and `connect` to the URI.
3. **Discovery:** `appNavigation.goToPage` appears as a first-class tool with a `page`
   enum; `appNavigation.getPageInfo` does **not** (schema-less) but still shows under
   `list_custom_extensions` and is callable via `call_custom_extension`.
4. **Validation:** `goToPage(page: <valid>)` navigates; invalid/missing `page` is rejected
   by schema validation.
5. **Coercion fix check:** call `call_custom_extension` with a nested `args` value and an
   extension that echoes its raw params; confirm the Flutter side receives valid JSON
   (post-fix) rather than `{min: 1}`-style Dart `toString()`.

### Lifecycle edge cases (the reconnect "revival" hack)
| Scenario | Expected |
|---|---|
| Disconnect, list tools | promoted tools gone; calling one rejected |
| Reconnect | tools reappear, callable, **no duplicate-registration crash** |
| Reconnect after changing description/enum | updated schema reflected |
| Reconnect without clean disconnect (kill app) | leftovers disabled then re-registered; no leak |
| Extension named like a built-in (`tap`) | skipped with warning; built-in unaffected |
| Malformed schema among several | that one skipped, rest promoted |
| `listExtensions` fails | connect still succeeds; `call_custom_extension` still works |

---

## 6. Related known issue (context only — NOT the fix target)

The reconnect "revival" workaround exists because `mcp_dart`'s `RegisteredTool.remove()` is
a no-op on the registry map: `remove()` → `update(name: null)`, and both map-mutating
branches are guarded by `name != null`, so the entry is never deleted (and re-registering
the name throws `ArgumentError`). Confirmed still present on `mcp_dart` `main`
(latest 2.2.1). If you bump the `mcp_dart` constraint, the workaround is still required —
do **not** assume a newer version lets you switch to `remove()` + re-`registerTool`.
A proper upstream fix would make `remove()` unconditionally
`_server._registeredTools.remove(this.name)`.

---

## 7. Suggested commit / PR hygiene
- Keep the coercion fix + its tests in one focused commit.
- Run the full per-package CI commands (section 3) before pushing.
- The PR also bundles regenerated example iOS files (commit `f8d4188`); leave them unless
  asked — they're unrelated to this fix.
