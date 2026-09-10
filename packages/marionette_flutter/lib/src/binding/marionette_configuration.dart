import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/services/log_collector.dart';

/// How much `get_interactive_elements` reduces its per-element payload.
///
/// Every level reports only primitive-valued properties — `ButtonStyle`,
/// `TextStyle`, `InputDecoration` and colour blobs never reach the agent,
/// because no interaction tool can act on them.
///
/// Only the two levels below exist. A third, `ultra` — per-snapshot element
/// refs in place of `bounds`, and one row per control — is planned, but none
/// of that behaviour is written yet. Shipping a value that silently behaves
/// like [compact] would mislead, and adding a value to an enum later is
/// additive.
enum CompactionMode {
  /// Report every primitive property the widget declares.
  none,

  /// Additionally drop rendering details no interaction tool reads
  /// (`textAlign`, `softWrap`, `overflow`, …) and the text-style primitives a
  /// `Text` inlines, drop `Text`'s `data` when it repeats `text`, round
  /// `bounds` to whole logical pixels, and report `visible` only when an
  /// element is not visible.
  compact,
}

/// Configuration for the Marionette extensions.
///
/// Provides support for custom app-specific widgets.
/// Standard Flutter widgets (TextField, Button, Text, etc.) are supported by
/// default.
///
/// Explicit `Semantics(label: ...)` / `Semantics(value: ...)` annotations are
/// surfaced in `get_interactive_elements` as a discovery-only fallback (see
/// `ElementTreeFinder` for the implementation). They are intentionally NOT
/// consulted by [extractTextFromWidget], which is the matcher path used by
/// `tap`/`scroll_to`/`enter_text` — otherwise a `Semantics(label: 'Save',
/// child: ElevatedButton(...))` wrapper would shadow the inner button and
/// redirect interactions to the wrapper node.
class MarionetteConfiguration {
  const MarionetteConfiguration({
    @Deprecated(
      'Use isInteractiveElement instead. '
      'It will be removed in a future release.',
    )
    this.isInteractiveWidget,
    this.isInteractiveElement,
    @Deprecated(
      'Use shouldStopTraversalAtElement instead. '
      'It will be removed in a future release.',
    )
    this.shouldStopTraversal,
    this.shouldStopTraversalAtElement,
    this.extractText,
    this.maxScreenshotSize = const Size(2000, 2000),
    this.compaction = CompactionMode.compact,
    this.logCollector,
    this.enableSessionReports = false,
  });

  /// Determines if an app-specific widget type is interactive.
  ///
  /// This is called only after checking built-in Flutter widgets.
  /// Return true for custom widgets that should be included
  /// in the interactive elements tree (e.g., custom buttons, text fields).
  ///
  /// A [Type] can only be compared with `==`, so this callback can't match
  /// generic widgets (`DsSelect<String>`), subclasses, or decide per
  /// instance. Use [isInteractiveElement] instead. While both are set, a
  /// widget is interactive when either of them returns true.
  @Deprecated(
    'Use isInteractiveElement instead. '
    'It will be removed in a future release.',
  )
  final bool Function(Type type)? isInteractiveWidget;

  /// Determines if an app-specific widget is interactive.
  ///
  /// This is called only after checking built-in Flutter widgets.
  /// Return true for custom widgets that should be included
  /// in the interactive elements tree (e.g., custom buttons, text fields).
  ///
  /// The callback receives the [Element], so it can match generic widgets
  /// and class hierarchies with an `is` check on `element.widget`, decide
  /// from the widget's fields, or look at the element's ancestors.
  ///
  /// Example:
  /// ```dart
  /// MarionetteConfiguration(
  ///   isInteractiveElement: (element) => switch (element.widget) {
  ///     MyButton() || MySelect() => true,
  ///     MyTile(:final onTap) => onTap != null,
  ///     _ => false,
  ///   },
  /// )
  /// ```
  final bool Function(Element element)? isInteractiveElement;

  /// Determines if traversal should stop at an app-specific widget type.
  ///
  /// This is called only after checking built-in Flutter widgets.
  /// Return true for custom widgets that should stop tree traversal.
  ///
  /// A [Type] can only be compared with `==`, so this callback can't match
  /// generic widgets, subclasses, or decide per instance. Use
  /// [shouldStopTraversalAtElement] instead. While both are set, traversal
  /// stops when either of them returns true.
  @Deprecated(
    'Use shouldStopTraversalAtElement instead. '
    'It will be removed in a future release.',
  )
  final bool Function(Type type)? shouldStopTraversal;

  /// Determines if traversal should stop at an app-specific widget.
  ///
  /// This is called only after checking built-in Flutter widgets.
  /// Return true for custom widgets whose descendants should be skipped
  /// during tree traversal. The widget itself is still discovered.
  ///
  /// The callback receives the [Element], so it can match generic widgets
  /// and class hierarchies with an `is` check on `element.widget`, or decide
  /// from the widget's fields.
  ///
  /// Most apps should leave this null: stopping too early hides content the
  /// agent needs to reach. Never stop at scroll containers.
  final bool Function(Element element)? shouldStopTraversalAtElement;

  /// Extracts text content from an app-specific widget instance.
  ///
  /// This callback serves two purposes:
  /// 1. **Element discovery**: Widgets with extractable text are included in
  ///    the interactive elements tree returned by `get_interactive_elements`,
  ///    even if they are not explicitly interactive. The extracted text is
  ///    exposed in the element's `text` field.
  /// 2. **Text-based matching**: The `tap`, `scroll_to`, and other interaction
  ///    tools can match elements by their text content using the `text`
  ///    parameter.
  ///
  /// This callback is called only after checking built-in Flutter widgets
  /// (Text, RichText, EditableText, TextField, TextFormField).
  /// Return the text content of your custom widgets, or null if not applicable.
  ///
  /// Example:
  /// ```dart
  /// MarionetteConfiguration(
  ///   extractText: (element) {
  ///     final widget = element.widget;
  ///     if (widget is MyCustomLabel) return widget.labelText;
  ///     if (widget is MyCustomInput) return widget.controller.text;
  ///     return null;
  ///   },
  /// )
  /// ```
  final String? Function(Element element)? extractText;

  /// Maximum size for screenshots in physical pixels.
  ///
  /// If set, captured screenshots will be downscaled to fit within this size
  /// while preserving aspect ratio. Set to null to disable resizing.
  final Size? maxScreenshotSize;

  /// How much `get_interactive_elements` reduces its payload by default.
  ///
  /// Defaults to [CompactionMode.compact]; see [CompactionMode] for what each
  /// level drops.
  ///
  /// The `compaction` parameter of `get_interactive_elements` overrides this
  /// in both directions, so an agent can still ask for the full payload on an
  /// app that keeps the default.
  final CompactionMode compaction;

  /// Optional log collector for capturing application logs.
  ///
  /// If not provided, the `get_logs` MCP tool will return an error with
  /// instructions on how to configure logging.
  ///
  /// ## Using the `logging` package
  ///
  /// ```dart
  /// import 'package:marionette_logging/marionette_logging.dart';
  ///
  /// MarionetteBinding.ensureInitialized(
  ///   MarionetteConfiguration(logCollector: LoggingLogCollector()),
  /// );
  /// ```
  ///
  /// ## Using the `logger` package
  ///
  /// ```dart
  /// import 'package:marionette_logger/marionette_logger.dart';
  ///
  /// final collector = LoggerLogCollector();
  /// MarionetteBinding.ensureInitialized(
  ///   MarionetteConfiguration(logCollector: collector),
  /// );
  /// final logger = Logger(output: MultiOutput([ConsoleOutput(), collector]));
  /// ```
  ///
  /// ## Using PrintLogCollector for custom logging
  ///
  /// ```dart
  /// final collector = PrintLogCollector();
  /// MarionetteBinding.ensureInitialized(
  ///   MarionetteConfiguration(logCollector: collector),
  /// );
  /// // Call collector.addLog(message) from your logging listener
  /// ```
  final LogCollector? logCollector;

  /// Whether a connected agent should record a session report for its run.
  ///
  /// When true, every `connect` (and every `marionette` CLI command) opens a
  /// fresh session directory under `.marionette/sessions/`, holding a
  /// machine-appended `steps.md` log, any screenshots saved with
  /// `take_screenshots(inline: false)`, and the agent-written `report.md`.
  /// Off by default, so nothing is written to disk unless you opt in.
  ///
  /// ```dart
  /// MarionetteBinding.ensureInitialized(
  ///   const MarionetteConfiguration(enableSessionReports: true),
  /// );
  /// ```
  ///
  /// See https://github.com/leancodepl/marionette_mcp/blob/main/docs/session-reports.md
  final bool enableSessionReports;

  /// Checks if an element's widget is interactive (built-in + custom).
  bool isElementInteractive(Element element) {
    final widget = element.widget;
    return _isBuiltInInteractiveWidget(widget) ||
        // ignore: deprecated_member_use_from_same_package
        (isInteractiveWidget?.call(widget.runtimeType) ?? false) ||
        (isInteractiveElement?.call(element) ?? false);
  }

  /// Returns whether traversal should stop at the given element.
  bool shouldStopAtElement(Element element) {
    final widget = element.widget;
    return _isBuiltInStopWidget(widget) ||
        // ignore: deprecated_member_use_from_same_package
        (shouldStopTraversal?.call(widget.runtimeType) ?? false) ||
        (shouldStopTraversalAtElement?.call(element) ?? false);
  }

  /// Checks if a widget type is interactive (built-in + custom).
  ///
  /// Compares types exactly, so it doesn't recognize generic built-in widgets
  /// such as `DropdownButton<String>`, or subclasses. Ignores
  /// [isInteractiveElement].
  @Deprecated(
    'Use isElementInteractive instead. '
    'It will be removed in a future release.',
  )
  bool isInteractiveWidgetType(Type type) {
    return _isBuiltInInteractiveType(type) ||
        // ignore: deprecated_member_use_from_same_package
        (isInteractiveWidget?.call(type) ?? false);
  }

  /// Returns whether traversal should stop at the given widget type.
  ///
  /// Compares types exactly, so it doesn't recognize generic built-in widgets
  /// or subclasses. Ignores [shouldStopTraversalAtElement].
  @Deprecated(
    'Use shouldStopAtElement instead. '
    'It will be removed in a future release.',
  )
  bool shouldStopAtType(Type type) {
    return _isBuiltInStopType(type) ||
        // ignore: deprecated_member_use_from_same_package
        (shouldStopTraversal?.call(type) ?? false);
  }

  /// Extracts text from a widget (built-in + custom).
  String? extractTextFromWidget(Element element) {
    final builtInText = _extractBuiltInText(element.widget);
    return builtInText ?? extractText?.call(element);
  }

  // Built-in Flutter widget support

  /// Matches with `is`, so generic widgets (`DropdownButton<String>`) and
  /// subclasses (the private button returned by `ElevatedButton.icon`) are
  /// recognized too.
  static bool _isBuiltInInteractiveWidget(Widget widget) {
    return switch (widget) {
      Checkbox() ||
      CheckboxListTile() ||
      DropdownButton() ||
      DropdownButtonFormField() ||
      FloatingActionButton() ||
      GestureDetector() ||
      IconButton() ||
      InkWell() ||
      PopupMenuButton() ||
      Radio() ||
      RadioListTile() ||
      Slider() ||
      Switch() ||
      SwitchListTile() ||
      TextField() ||
      TextFormField() ||
      // ElevatedButton, FilledButton, OutlinedButton, TextButton and their
      // private variants, such as the one returned by ElevatedButton.icon.
      ButtonStyleButton() =>
        true,
      _ => false,
    };
  }

  /// Built-in interactive widgets whose descendants are still traversed.
  ///
  /// [GestureDetector] and [InkWell] usually wrap content. The others show
  /// their label or selected value in a child that would otherwise be hidden
  /// from discovery.
  static bool _isBuiltInPassThroughWidget(Widget widget) {
    return switch (widget) {
      GestureDetector() ||
      InkWell() ||
      DropdownButton() ||
      DropdownButtonFormField() ||
      PopupMenuButton() ||
      RadioListTile() =>
        true,
      _ => false,
    };
  }

  static bool _isBuiltInStopWidget(Widget widget) {
    return !_isBuiltInPassThroughWidget(widget) &&
        (_isBuiltInInteractiveWidget(widget) || widget is Text);
  }

  // Exact type comparisons used only by the deprecated Type-based methods.
  // Remove together with them.

  static bool _isBuiltInInteractiveType(Type type) {
    return type == Checkbox ||
        type == CheckboxListTile ||
        type == DropdownButton ||
        type == DropdownButtonFormField ||
        type == ElevatedButton ||
        type == FilledButton ||
        type == FloatingActionButton ||
        type == GestureDetector ||
        type == IconButton ||
        type == InkWell ||
        type == OutlinedButton ||
        type == PopupMenuButton ||
        type == Radio ||
        type == RadioListTile ||
        type == Slider ||
        type == Switch ||
        type == SwitchListTile ||
        type == TextButton ||
        type == TextField ||
        type == TextFormField ||
        type == ButtonStyleButton;
  }

  static bool _isBuiltInStopType(Type type) {
    return (type != GestureDetector && type != InkWell) &&
        (_isBuiltInInteractiveType(type) || type == Text);
  }

  static String? _extractBuiltInText(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is EditableText) {
      return widget.controller.text;
    }
    if (widget is TextField) {
      return widget.controller?.text;
    }
    if (widget is TextFormField) {
      return widget.controller?.text;
    }
    return null;
  }
}
