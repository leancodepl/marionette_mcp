# Configuration

`MarionetteConfiguration` is how you teach Marionette about your app. **If your app uses a custom design system, this page is mandatory, not optional.** Most "Marionette can't find my button / can't type in my field" problems are missing configuration, not bugs.

Start with the [Production Setup Checklist](#production-setup-checklist), then drill into the callback that addresses your symptom.

## Production Setup Checklist

Each callback fixes a specific failure mode. Map your symptom to the fix:

| Symptom | Cause | Fix |
| --- | --- | --- |
| Your custom buttons / controls don't appear in `get_interactive_elements` | The widget type isn't recognized as interactive | Add it to [`isInteractiveWidget`](#isinteractivewidget) |
| `tap(text:)` / `scroll_to(text:)` can't find a custom field or label by its text | Text isn't being extracted from the widget | Implement [`extractText`](#extracttext) for that widget |
| `get_logs` returns a "no LogCollector configured" message | No log collector is wired up | Set [`logCollector`](./logging.md) |
| Custom-painted text, badges, or charts are invisible to the agent | The text never reaches a `Text` widget | Annotate with [`Semantics`](./semantics.md) |
| Widget coverage looks low / the agent can't reach nested content | Over-aggressive traversal stopping | **Leave [`shouldStopTraversal`](#shouldstoptraversal) `null`** — do not filter scroll containers |

A complete `main.dart` that wires all of these together is at the [bottom of this page](#complete-production-maindart).

## What works out of the box

With no configuration, Marionette recognizes the standard Flutter widgets.

**Interactive (returned by `get_interactive_elements`, targetable by `tap`):** `Checkbox`, `CheckboxListTile`, `DropdownButton`, `DropdownButtonFormField`, `ElevatedButton`, `FilledButton`, `FloatingActionButton`, `GestureDetector`, `IconButton`, `InkWell`, `OutlinedButton`, `PopupMenuButton`, `Radio`, `RadioListTile`, `Slider`, `Switch`, `SwitchListTile`, `TextButton`, `TextField`, `TextFormField`, `ButtonStyleButton`.

**Text extraction (used for `tap(text:)` matching and shown in element output):** `Text`, `RichText`, `EditableText`, `TextField`, `TextFormField`.

If your widgets wrap or replace these — e.g. a `MyPrimaryButton` built on a `GestureDetector`, or a `MyText` that isn't a `Text` — Marionette won't know about them until you tell it. That's what the callbacks below are for.

## Configuration reference

`MarionetteConfiguration` is passed to `MarionetteBinding.ensureInitialized(...)` as an optional positional argument. All fields are optional and named:

| Field | Type | Default | Purpose |
| --- | --- | --- | --- |
| `isInteractiveWidget` | `bool Function(Type type)?` | `null` | Mark app-specific widget types as interactive. |
| `extractText` | `String? Function(Element element)?` | `null` | Extract display text from app-specific widgets. |
| `logCollector` | `LogCollector?` | `null` | Capture app logs for `get_logs`. See [Logging](./logging.md). |
| `shouldStopTraversal` | `bool Function(Type type)?` | `null` | Stop descending below given widget types. **Rarely needed** — see below. |
| `maxScreenshotSize` | `Size?` | `Size(2000, 2000)` | Downscale screenshots to fit; `null` disables resizing. |

Your callbacks run **after** the built-in checks — you're extending the defaults, not replacing them.

### `isInteractiveWidget`

A typical screen has hundreds of widgets (`Padding`, `Container`, `Column`, `SizedBox`, …). `get_interactive_elements` filters that down to actionable targets so the agent gets a concise list instead of an overwhelming dump. Custom widgets aren't on the built-in list, so mark them:

```dart
MarionetteConfiguration(
  isInteractiveWidget: (type) =>
      type == MyPrimaryButton || type == MyTextField,
)
```

Now `MyPrimaryButton` and `MyTextField` appear in the element list and can be targeted by `tap` and friends.

### `extractText`

`extractText` serves two purposes:

1. **Element discovery** — widgets with extractable text are included in `get_interactive_elements` (even if not interactive), and the text appears in the element's `text` field so the agent knows what each element shows.
2. **Text-based matching** — `tap` and `scroll_to` can match by visible text via the `text` parameter (e.g. `tap(text: "Submit")`). (`enter_text` is the exception: it targets a field by `key`, or by focusing it first via `tap` and passing `focused_element: true` — it has no `text` matcher.)

The callback receives the `Element` (access the widget via `element.widget`), which lets you walk the subtree — essential when a label or placeholder is itself a `Widget` rather than a plain `String`.

```dart
MarionetteConfiguration(
  extractText: (element) {
    final widget = element.widget;
    if (widget is MyText) return widget.data;          // data is a String
    if (widget is MyTextField) {
      return _extractMyTextFieldText(element, widget);  // label is a Widget
    }
    return null;
  },
)
```

<details>
<summary>Full example: extracting text from a custom field whose label is a widget</summary>

When a custom field's label lives inside a child widget (not a plain string), walk the element tree to find the rendered text:

```dart
/// Extracts label text from a MyTextField by walking the element tree.
/// The label lives inside a MyInputDecorator child widget, so we first
/// find the decorator by type, then extract the rendered text from its
/// label widget.
String? _extractMyTextFieldText(Element element, MyTextField widget) {
  final decorator = _findElementOfType<MyInputDecorator>(element);
  if (decorator != null) {
    final decoratorWidget = decorator.widget as MyInputDecorator;
    if (decoratorWidget.label != null) {
      final label = _findTextInWidgetSlot(decorator, decoratorWidget.label!);
      if (label != null) return label;
    }
  }
  // Fall back to current value
  return widget.controller?.text;
}

/// Finds the first descendant Element whose widget is type [T].
Element? _findElementOfType<T extends Widget>(Element root) {
  Element? found;
  root.visitChildren((child) {
    if (found != null) return;
    if (child.widget is T) {
      found = child;
    } else {
      found = _findElementOfType<T>(child);
    }
  });
  return found;
}

/// Finds the Element for [targetWidget] under [parent], then
/// collects all rendered text beneath it.
String? _findTextInWidgetSlot(Element parent, Widget targetWidget) {
  Element? slotElement;
  parent.visitChildren((child) {
    if (slotElement != null) return;
    if (identical(child.widget, targetWidget)) {
      slotElement = child;
    } else {
      slotElement = _findElementForWidget(child, targetWidget);
    }
  });
  if (slotElement == null) return null;

  final buffer = StringBuffer();
  _collectText(slotElement!, buffer);
  final result = buffer.toString().trim();
  return result.isEmpty ? null : result;
}

Element? _findElementForWidget(Element root, Widget target) {
  Element? found;
  root.visitChildren((child) {
    if (found != null) return;
    if (identical(child.widget, target)) {
      found = child;
    } else {
      found = _findElementForWidget(child, target);
    }
  });
  return found;
}

void _collectText(Element element, StringBuffer buffer) {
  final widget = element.widget;
  if (widget is Text && widget.data != null) {
    if (buffer.isNotEmpty) buffer.write(' ');
    buffer.write(widget.data);
    return;
  }
  if (widget is RichText) {
    final plain = widget.text.toPlainText();
    if (plain.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(plain);
    }
    return;
  }
  element.visitChildren((child) => _collectText(child, buffer));
}
```

</details>

> Custom-rendered content with no underlying `Text` (custom paint, `WidgetSpan`, charts) needs a different tool — see [Semantics](./semantics.md).

### `shouldStopTraversal`

> [!WARNING]
> **Most apps should leave this `null`.** It is an easy footgun.

`shouldStopTraversal` tells Marionette to stop descending **below** a widget type during tree traversal. The widget itself is still discovered — only its descendants are skipped. By default Marionette stops at interactive leaf widgets (and `Text`) but keeps descending through `GestureDetector` and `InkWell`, which usually wrap content.

It is tempting to add scroll containers here to "reduce traversal cost." **Don't.** In production testing on a large app, filtering scroll containers *reduced* widget coverage from **25.8% to 17.8%** — the agent lost sight of everything below the stop point, including content it needed to act on.

Only add a type after profiling shows a real, measured win, and never a scrolling container. If you're not sure, leave it `null`.

### `maxScreenshotSize`

By default screenshots are downscaled to fit within `2000 × 2000` physical pixels to keep payloads manageable. Override it, or set it to `null` to disable resizing:

```dart
MarionetteConfiguration(maxScreenshotSize: Size(1280, 1280))
```

## Complete production `main.dart`

A copy-pasteable starting point that wires every callback plus a log hook. Adapt the widget types to your design system.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

// Your design system + logging.
import 'package:my_app/design_system/button.dart';
import 'package:my_app/design_system/text.dart';
import 'package:my_app/design_system/text_field.dart';

void main() {
  if (kDebugMode) {
    final logCollector = PrintLogCollector();

    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(
        // 1. Recognize your custom interactive widgets.
        isInteractiveWidget: (type) =>
            type == MyPrimaryButton || type == MyTextField,

        // 2. Extract text so agents can match by visible label.
        extractText: (element) {
          final widget = element.widget;
          if (widget is MyText) return widget.data;
          if (widget is MyTextField) {
            return _extractMyTextFieldText(element, widget);
          }
          return null;
        },

        // 3. Collect logs for get_logs.
        logCollector: logCollector,

        // 4. Leave shouldStopTraversal null unless profiling proves a win.

        // 5. (Optional) tune screenshot size.
        // maxScreenshotSize: const Size(1280, 1280),
      ),
    );

    // Route your app's logs into the collector.
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logCollector.addLog(message);
      debugPrintSynchronously(message, wrapWidth: wrapWidth);
    };
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  runApp(const MyApp());
}

// _extractMyTextFieldText and helpers: see the "Full example" above.
```

> Prefer the `logging` or `logger` package over a `debugPrint` hook? See [Log Collection](./logging.md) for first-class adapters.
