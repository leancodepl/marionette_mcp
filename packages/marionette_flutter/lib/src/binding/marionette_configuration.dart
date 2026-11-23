import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_control_kind.dart';
import 'package:marionette_flutter/src/binding/marionette_ui_library.dart';
import 'package:marionette_flutter/src/services/log_collector.dart';

class _AdditionalWidgetSupport {
  const _AdditionalWidgetSupport({
    required this.library,
    required this.isInteractiveElement,
    required this.shouldStopTraversalAtElement,
    required this.extractText,
    required this.controlKind,
    required this.extractFieldLabel,
  });

  final MarionetteUiLibrary library;
  final bool Function(Element element) isInteractiveElement;
  final bool Function(Element element) shouldStopTraversalAtElement;
  final String? Function(Element element) extractText;
  final MarionetteControlKind? Function(Element element) controlKind;
  final String? Function(Element element) extractFieldLabel;
}

/// How much `get_interactive_elements` reduces its payload. [compact] can also
/// leave out an element whose only content is an icon-font glyph: text made
/// only of Unicode private-use characters (see [compact]).
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

  /// Additionally drop icon-font glyphs, rendering details no interaction tool
  /// reads (`textAlign`, `softWrap`, `overflow`, …) and the text-style
  /// primitives a `Text` inlines, drop `Text`'s `data` when it repeats `text`,
  /// round `bounds` to whole logical pixels, and report `visible` only when an
  /// element is not visible.
  ///
  /// A glyph is text made only of Unicode private-use characters, which is how
  /// an icon font draws an `Icon`. An element whose only content is a glyph is
  /// left out, so an `Icon` outside an interactive widget is not listed as a
  /// `RichText`. A key or a Semantics identifier on the element keeps it
  /// listed. An `Icon`'s `semanticLabel` is reported as `text` by the
  /// `Semantics` widget that the `Icon` wraps around the glyph.
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
    bool Function(Type type)? isInteractiveWidget,
    this.isInteractiveElement,
    @Deprecated(
      'Use shouldStopTraversalAtElement instead. '
      'It will be removed in a future release.',
    )
    bool Function(Type type)? shouldStopTraversal,
    this.shouldStopTraversalAtElement,
    this.extractText,
    this.controlKind,
    this.extractFieldLabel,
    this.maxScreenshotSize = const Size(2000, 2000),
    this.compaction = CompactionMode.compact,
    this.logCollector,
    this.enableSessionReports = false,
  })  : _isInteractiveWidget = isInteractiveWidget,
        _shouldStopTraversal = shouldStopTraversal,
        _additionalWidgetSupport = const [];

  MarionetteConfiguration._({
    required bool Function(Type type)? isInteractiveWidget,
    required this.isInteractiveElement,
    required bool Function(Type type)? shouldStopTraversal,
    required this.shouldStopTraversalAtElement,
    required this.extractText,
    required this.controlKind,
    required this.extractFieldLabel,
    required this.maxScreenshotSize,
    required this.compaction,
    required this.logCollector,
    required this.enableSessionReports,
    required List<_AdditionalWidgetSupport> additionalWidgetSupport,
  })  : _isInteractiveWidget = isInteractiveWidget,
        _shouldStopTraversal = shouldStopTraversal,
        _additionalWidgetSupport = List.unmodifiable(additionalWidgetSupport);

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
  bool Function(Type type)? get isInteractiveWidget => _isInteractiveWidget;
  final bool Function(Type type)? _isInteractiveWidget;

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
  bool Function(Type type)? get shouldStopTraversal => _shouldStopTraversal;
  final bool Function(Type type)? _shouldStopTraversal;

  /// Determines if traversal should stop at an app-specific widget.
  ///
  /// This is called only after checking built-in Flutter widgets.
  /// Return true for custom widgets whose descendants (except toggles) should
  /// be skipped during tree traversal. The widget itself is still discovered.
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
  /// (Text, RichText, EditableText, TextField, TextFormField). For a text
  /// field built without a controller, it runs before the fallback that
  /// reports the typed text, so the text it returns wins.
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

  /// Tells which typed control an app-specific widget is, so discovery reads
  /// its value or state as for a built-in text field, toggle or radio.
  /// Return null if not applicable.
  ///
  /// It runs before the rules of the optional UI integrations, so the kind it
  /// returns wins.
  final MarionetteControlKind? Function(Element element)? controlKind;

  /// Extracts the label of an app-specific text field, which discovery
  /// reports apart from the field's value. Return null if not applicable.
  ///
  /// It runs before the rules of the optional UI integrations, so the label
  /// it returns wins.
  final String? Function(Element element)? extractFieldLabel;

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

  final List<_AdditionalWidgetSupport> _additionalWidgetSupport;

  /// The optional UI rules actively composed into this configuration.
  Set<MarionetteUiLibrary> get uiLibraries => Set.unmodifiable({
        for (final library in MarionetteUiLibrary.values)
          if (_additionalWidgetSupport.any(
            (support) => support.library == library,
          ))
            library,
      });

  /// Composes typed rules for one optional UI library into this configuration.
  /// Reapplying the same library is idempotent.
  MarionetteConfiguration withAdditionalWidgetSupport({
    required MarionetteUiLibrary library,
    required bool Function(Element element) isInteractiveElement,
    required bool Function(Element element) shouldStopTraversalAtElement,
    required String? Function(Element element) extractText,
    required MarionetteControlKind? Function(Element element) controlKind,
    required String? Function(Element element) extractFieldLabel,
  }) {
    if (uiLibraries.contains(library)) return this;
    return MarionetteConfiguration._(
      isInteractiveWidget: _isInteractiveWidget,
      isInteractiveElement: this.isInteractiveElement,
      shouldStopTraversal: _shouldStopTraversal,
      shouldStopTraversalAtElement: this.shouldStopTraversalAtElement,
      extractText: this.extractText,
      controlKind: this.controlKind,
      extractFieldLabel: this.extractFieldLabel,
      maxScreenshotSize: maxScreenshotSize,
      compaction: compaction,
      logCollector: logCollector,
      enableSessionReports: enableSessionReports,
      additionalWidgetSupport: [
        ..._additionalWidgetSupport,
        _AdditionalWidgetSupport(
          library: library,
          isInteractiveElement: isInteractiveElement,
          shouldStopTraversalAtElement: shouldStopTraversalAtElement,
          extractText: extractText,
          controlKind: controlKind,
          extractFieldLabel: extractFieldLabel,
        ),
      ],
    );
  }

  /// Checks if an element's widget is interactive (built-in + custom).
  bool isElementInteractive(Element element) {
    final widget = element.widget;
    return _isBuiltInInteractiveWidget(widget) ||
        // ignore: deprecated_member_use_from_same_package
        (isInteractiveWidget?.call(widget.runtimeType) ?? false) ||
        (isInteractiveElement?.call(element) ?? false) ||
        _additionalWidgetSupport.any(
          (support) => support.isInteractiveElement(element),
        );
  }

  /// Returns whether traversal should stop at the given element.
  bool shouldStopAtElement(Element element) {
    return _isBuiltInStopWidget(element.widget) ||
        shouldAppStopAtElement(element) ||
        _additionalWidgetSupport.any(
          (support) => support.shouldStopTraversalAtElement(element),
        );
  }

  /// Returns whether the app's own callbacks, [shouldStopTraversalAtElement]
  /// or the deprecated `shouldStopTraversal`, stop traversal at the given
  /// element.
  bool shouldAppStopAtElement(Element element) {
    // ignore: deprecated_member_use_from_same_package
    return (shouldStopTraversal?.call(element.widget.runtimeType) ?? false) ||
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
    final typedKind = controlKindFor(element);
    if (typedKind != null) {
      final appText = extractText?.call(element);
      if (appText != null) return appText;
      for (final support in _additionalWidgetSupport) {
        final integrationText = support.extractText(element);
        if (integrationText != null) return integrationText;
      }
      return _extractBuiltInText(element.widget) ??
          _extractControllerlessFieldText(element);
    }
    // The controller-less field fallback comes last so an app's own
    // extractText for such a field (e.g. one returning its label) still wins.
    final builtInText = _extractBuiltInText(element.widget);
    if (builtInText != null) return builtInText;
    final appText = extractText?.call(element);
    if (appText != null) return appText;
    for (final support in _additionalWidgetSupport) {
      final integrationText = support.extractText(element);
      if (integrationText != null) return integrationText;
    }
    return _extractControllerlessFieldText(element);
  }

  MarionetteControlKind? controlKindFor(Element element) {
    final appKind = controlKind?.call(element);
    if (appKind != null) return appKind;
    for (final support in _additionalWidgetSupport) {
      final kind = support.controlKind(element);
      if (kind != null) return kind;
    }
    return null;
  }

  String? fieldLabelFor(Element element) {
    final appLabel = extractFieldLabel?.call(element);
    if (appLabel != null) return appLabel;
    for (final support in _additionalWidgetSupport) {
      final label = support.extractFieldLabel(element);
      if (label != null) return label;
    }
    return null;
  }

  // Built-in Flutter widget support

  /// Matches with `is`, so generic widgets (`DropdownButton<String>`) and
  /// subclasses (the private button returned by `ElevatedButton.icon`) are
  /// recognized too.
  static bool _isBuiltInInteractiveWidget(Widget widget) {
    return switch (widget) {
      Checkbox() ||
      CheckboxListTile() ||
      CupertinoCheckbox() ||
      CupertinoRadio() ||
      CupertinoSwitch() ||
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
        type == CupertinoCheckbox ||
        type == CupertinoRadio ||
        type == CupertinoSwitch ||
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

  /// A `TextField`/`TextFormField` built without a `controller` creates one
  /// internally, so the typed value lives only on the inner [EditableText].
  static String? _extractControllerlessFieldText(Element element) {
    final widget = element.widget;
    if (widget is! TextField && widget is! TextFormField) return null;
    String? found;
    void visit(Element child) {
      if (found != null) return;
      final inner = child.widget;
      if (inner is EditableText) {
        found = inner.controller.text;
        return;
      }
      child.visitChildren(visit);
    }

    element.visitChildren(visit);
    return found;
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
