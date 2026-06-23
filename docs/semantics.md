# Making Complex Content Readable via `Semantics`

Most rich content is already extracted out of the box — `Text.rich` and `RichText` flatten their span tree via `toPlainText()`, so an agent reads the rendered plaintext without any extra annotation. `Semantics` is the escape hatch for the cases where that plaintext isn't enough or doesn't exist:

- **Custom-painted text** — `CustomPaint` and direct `TextPainter` rendering bypass the `Text` widget entirely, so there is nothing for `toPlainText()` to flatten.
- **Lossy `WidgetSpan` content** — `toPlainText()` cannot reach text rendered inside `WidgetSpan` children, so anything composed that way (badges, inline icons-with-text, embedded widgets) is invisible.
- **Raw-source preservation** — when you want the agent to see the markdown/markup source you parsed, not the rendered plaintext (e.g. so it can reason about structure), `Semantics(label: rawSource)` carries that through.

The fix is the same primitive screen readers already rely on: wrap the visual widget in `Semantics` and supply an explicit `label` (or `value`). Marionette surfaces these annotations in `get_interactive_elements` as `Type: Semantics, text: "<label>"`, giving agents a stable, structured channel alongside whatever `toPlainText()` already produced.

```dart
// Structural label + dynamic value. Both the screen reader
// ("Volume, 70 percent") and the agent (Type: Semantics, text:
// "Volume: 70%") get clean, human-friendly strings.
Semantics(
  label: 'Volume',
  value: '70%',
  child: CustomPaint(painter: _VolumeBarPainter(level: 0.7)),
)
```

When both `label` and `value` are set, Marionette joins them as `'label: value'` in the discovery output, so widgets with dynamic state (sliders, progress bars, gauges) keep their current value visible to agents instead of dropping it.

This works without any `extractText` configuration. The same technique works for tables, lists, charts, badges, and any custom-rendered content where you want to give an agent a single authoritative summary instead of asking it to reconstruct meaning from a flat list of cells.

## Discovery-only contract for `label` / `value`

`Semantics` **`label` and `value`** annotations are surfaced as a **discovery-only** fallback in `get_interactive_elements` — they are **not** consulted by the matcher path used by `tap`, `scroll_to`, and `enter_text`. So wrapping a control in `Semantics(label: ...)` will **not** cause gestures to be redirected to the wrapper instead of the inner widget.

This is deliberate: a `label` like `"Submit"` would otherwise collide with the rendered `Text("Submit")`, leaving the matcher unable to tell the `Semantics` wrapper apart from the real control. Keeping `label`/`value` out of matching avoids that ambiguity.

`Semantics` widgets without an explicit `label` or `value` (framework-generated annotations with no user-visible content) are **not** reported, so the output stays quiet by default.

## Matching by `identifier`

The `Semantics` **`identifier`** is different. Unlike `label`/`value` it is an explicit, unique, machine-readable handle that you set on purpose — and it lives only on the `Semantics` widget, never on the inner control — so there is no ambiguity about which element it refers to. Marionette therefore **does** consult `identifier` in the matcher path: `tap`, `double_tap`, `secondary_tap`, `long_press`, `swipe`, `pinch_zoom`, `scroll_to`, and `enter_text` all accept an `identifier` selector (in the CLI: `--identifier`).

```dart
// No ValueKey, but a stable Semantics identifier the agent can target.
Semantics(
  identifier: 'submit_button',
  child: ElevatedButton(onPressed: _submit, child: const Text('Submit')),
)
```

Because the `Semantics` wrapper shares the bounds of (and is hittable through) its child, a tap matched by `identifier` lands on the real control underneath. This makes `identifier` an equally stable alternative to a `ValueKey` for elements you cannot — or would rather not — assign a key to. The `identifier` is also surfaced in `get_interactive_elements` (for hittable elements, like every other discovery entry) so agents can discover it.

Convenience parameters that forward to a generated `Semantics` wrapper are covered by the same mechanism — no special handling required. For example `Text('Submit', semanticsIdentifier: 'submit_btn')` builds a `Semantics(identifier: 'submit_btn')` internally, so `identifier: 'submit_btn'` matches it just like an explicit wrapper.

One thing it does **not** cover: per-span identifiers set via `TextSpan.semanticsIdentifier` / `InlineSpan.semanticsIdentifier`. Those are applied at the `SemanticsNode` level inside `RenderParagraph`, not as a widget in the tree, so there is no element for the matcher to match. If you need to target a specific run of rich text, wrap it in an explicit `Semantics(identifier: ...)` (or split it into its own `Text`) instead.

## Accessibility trade-off: keep `label` human-friendly

Whatever you put in `Semantics.label` is announced verbatim by VoiceOver and TalkBack. Stuffing markup, raw markdown, or machine-readable identifiers into `label` so the agent can read them will degrade the experience for screen-reader users — `**bold**` is read as "star star bold star star", not "bold". Two patterns avoid the trade-off:

- **Pattern A — clean label, render via `Text.rich`.** Keep `label` as the human-friendly string and let `Text.rich.toPlainText()` cover the rendered version. Both the agent and the screen reader get clean text; the agent simply sees two complementary entries (`Type: Semantics` + `Type: Text`).
- **Pattern B — structural label + dynamic value.** Use `label` for what the control *is* and `value` for its current state. Marionette emits the combined `'label: value'` for agents; screen readers announce the pair the same way they announce a native slider.
- **Pattern C — machine-readable selector via `identifier`.** When all you want is a stable handle for the agent to *target* (not read aloud), put it in `Semantics.identifier`, not `label`. The `identifier` is never announced by VoiceOver/TalkBack, so a value like `submit_button` stays invisible to screen-reader users while remaining a first-class matcher for `tap`, `enter_text`, and the other gesture tools. This is the recommended home for machine-readable selectors and avoids polluting `label` with non-human-friendly strings.

If your `label` is genuinely not human-readable (e.g. you really do want the agent to see raw markup), prefer a custom widget with [`extractText`](./configuration.md#extracttext) so the markup never reaches the accessibility tree.
