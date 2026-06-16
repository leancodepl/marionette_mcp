# Troubleshooting

## Common gotchas

Most "Marionette doesn't work" reports trace back to missing configuration. Match your symptom:

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Custom buttons / controls don't show up in `get_interactive_elements` | Custom widget type isn't recognized as interactive | Add it to [`isInteractiveWidget`](./configuration.md#isinteractivewidget) |
| `tap(text:)` / `scroll_to(text:)` can't find a custom field or label | Text isn't extracted from the widget | Implement [`extractText`](./configuration.md#extracttext) |
| Custom-painted text, badges, charts are invisible to the agent | Text never reaches a `Text` widget | Annotate with [`Semantics`](./semantics.md) |
| `get_logs` says no collector is configured | No `LogCollector` wired up | See [Log Collection](./logging.md) |
| Widget coverage looks low / agent can't reach nested content | Over-aggressive `shouldStopTraversal` | **Leave it `null`** — never filter scroll containers ([why](./configuration.md#shouldstoptraversal)) |
| Binding assertion error on startup, often in tests | Two `WidgetsBinding`s initialized | See the [single-binding rule](./flutter-setup.md#single-binding-rule) |
| `connect` fails with a version mismatch | `marionette_mcp`/`marionette_cli` and `marionette_flutter` are different versions | Align both packages to the same version |

## Quick fixes

- **"Not connected to any app"** — ensure the agent called `connect` with a valid VM Service URI before any other tool.
- **Finding the URI** — run your app in debug mode (`flutter run`) and look for a line like `... is available at: http://127.0.0.1:9101?uri=ws://127.0.0.1:9101/ws`. Use the `ws://...` part.
- **Release mode** — Marionette only works in **debug and profile** mode because it relies on the VM Service. It will not work in release builds.
- **Elements not found** — make sure the widget is actually visible on screen. If it's a custom widget, confirm it's covered by your [`MarionetteConfiguration`](./configuration.md).

## Assumptions & limitations

- **Prefer pasting the VM Service URI manually.** Some tooling can discover or infer the endpoint, but the most reliable workflow is to copy the `ws://.../ws` URI from your `flutter run` output (or a DevTools link) and paste it to the agent when calling `connect`.

- **The agent may not know your app.** Marionette can "see" the widget tree and interact with UI, but it doesn't automatically understand your product's flows, naming conventions, or edge cases. For reliable navigation and assertions, give the agent context in the prompt: what screen to reach, expected labels/keys, preconditions, and the goal of the interaction.

- **"Your mileage may vary" interactions.** Some actions are best-effort simulations of user behavior (gestures, focus, text entry, scrolling). Depending on platform, custom widgets, overlays, or app-specific gesture handling, results may vary. If a flow is flaky, consider exposing clearer widget keys, simplifying hit targets, or adding custom [`MarionetteConfiguration`](./configuration.md) hooks for your design system. If something consistently misbehaves, a small repro in an [issue](https://github.com/leancodepl/marionette_mcp/issues) helps us improve it.
