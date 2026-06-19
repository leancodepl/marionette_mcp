# Custom Extensions

Beyond the built-in tools, your app can expose its own actions to the agent by registering a custom VM service extension with `registerMarionetteExtension`. This is useful for app-specific operations the generic tools can't express — navigating by route name, seeding test data, toggling feature flags, and so on.

Register extensions wherever you set the app up (e.g. in `main()` after `MarionetteBinding.ensureInitialized()`), guarded by `kDebugMode` like the binding itself.

## Declaring a schema (recommended)

When an extension declares an `inputSchema`, the MCP server promotes it to a **first-class, individually-named tool** with a validated input schema. The agent discovers it in the tool list, gets argument hints and enum autocomplete, and invalid arguments are rejected before they ever reach your app:

```dart
import 'package:marionette_flutter/marionette_flutter.dart';

registerMarionetteExtension(
  name: 'appNavigation.goToPage',
  description: 'Navigates to a page by name.',
  inputSchema: ExtensionInputSchema(
    properties: {
      'page': ExtensionParam.string(
        description: 'The page to navigate to.',
        enumValues: ['home', 'profile', 'settings'],
      ),
      'animate': ExtensionParam.boolean(
        description: 'Whether to animate the transition.',
        defaultValue: true,
      ),
    },
    required: ['page'],
  ),
  callback: (params) async {
    final page = params['page'];
    if (page == null) {
      return MarionetteExtensionResult.invalidParams('Missing required parameter: page');
    }
    // `params` always arrives as Map<String, String>; parse non-string values.
    final animate = params['animate'] != 'false';
    navigateTo(page, animate: animate); // your app's own navigation
    return MarionetteExtensionResult.success({'page': page});
  },
);
```

The agent can now call this tool directly — e.g. _"navigate to the profile page"_ — and a bad value like `page: "banana"` is rejected by schema validation. The tool is exposed under a sanitized name (here `app_navigation_go_to_page`; see [Tool name sanitization](#tool-name-sanitization)), but you still invoke the extension by its real name through `call_custom_extension`.

`ExtensionParam` supports `.string` (with optional `enumValues`), `.integer`, `.number`, and `.boolean`. **Schemas are restricted to flat scalar parameters** by design: custom extension arguments travel over the VM service as a `Map<String, String>`, so nested objects/arrays can't round-trip reliably as typed values.

Any property that declares a `defaultValue` is filled in (as its string form) before your `callback` runs when the caller omits it — you don't have to reimplement the default you already declared.

## No schema (the fallback)

A schema is optional. An extension without one — e.g. a parameter-less action, or one whose inputs a scalar schema can't capture — stays fully supported: it is **not** promoted to its own tool, but remains reachable through the generic `call_custom_extension` tool and shows up in `list_custom_extensions`.

```dart
registerMarionetteExtension(
  name: 'appNavigation.getPageInfo',
  description: 'Returns the current page and the list of available pages.',
  callback: (params) async => MarionetteExtensionResult.success({
    'currentPage': currentPageName(),
    'availablePages': allPageNames(),
  }),
);
```

> **Prefer declaring an `inputSchema`** whenever your parameters are flat scalars — you get validation and a dedicated, discoverable tool. Reach for the schema-less form only for parameter-less extensions or inputs a scalar schema can't express.

## Tool name sanitization

The MCP spec itself doesn't constrain tool-name characters, but the LLM tool-calling APIs the names ultimately flow into do: Anthropic accepts `[a-zA-Z0-9_]`, OpenAI `[a-zA-Z0-9_-]` — both reject the `.` namespace separator. The `namespace.method` convention is therefore out of spec for essentially every client; clients just handle it differently (Claude Code silently rewrites the name, VS Code Copilot rejects anything outside `[a-z0-9_-]` and drops the tool). So when an extension is promoted to a first-class tool, its name is sanitized to the lowest common denominator `[a-z0-9_-]` for the MCP tool list: lower-cased, camelCase split on word boundaries, and every other disallowed character (such as the `.`) replaced with `_`. For example:

| Extension name | MCP tool name |
| --- | --- |
| `appNavigation.goToPage` | `app_navigation_go_to_page` |
| `analytics.flush` | `analytics_flush` |
| `already_valid-name` | `already_valid-name` (unchanged) |

The **extension is always invoked by its real name** — only the tool-list entry is renamed — and the real name is recorded in the tool's description so it stays reachable via `call_custom_extension`. If two extensions sanitize to the same tool name, only the first is promoted and the collision is logged; rename one on the Flutter side.

## Notes

- The `ext.flutter.` prefix is added automatically — pass the bare name (e.g. `appNavigation.goToPage`). Passing a name that already includes the prefix, or an empty name, throws `ArgumentError`.
- Extension names are sanitized to `[a-z0-9_-]` when promoted to MCP tools — see [Tool name sanitization](#tool-name-sanitization).
- Your `callback` returns a `MarionetteExtensionResult` — use `MarionetteExtensionResult.success(<map>)` or `MarionetteExtensionResult.invalidParams(<message>)`.
- For a runnable end-to-end demo, see the [example app](https://github.com/leancodepl/marionette_mcp/tree/main/example).

See also the [MCP Tools](./mcp-tools.md#custom-extensions) reference for `list_custom_extensions` and `call_custom_extension`.
