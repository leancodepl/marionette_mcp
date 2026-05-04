import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/services/log_collector.dart';

/// Configuration for the Marionette extensions.
///
/// Provides support for custom app-specific widgets.
/// Standard Flutter widgets (TextField, Button, Text, etc.) are supported by
/// default. Explicit `Semantics(label: ...)` annotations are also surfaced —
/// see [_extractBuiltInText] for the full list — which lets you make
/// otherwise-opaque content (composite `Text.rich` trees, custom-painted text,
/// third-party rich-text renderers) readable to AI agents without altering
/// rendering, using the same primitive that drives screen readers.
class MarionetteConfiguration {
  const MarionetteConfiguration({
    this.isInteractiveWidget,
    this.shouldStopTraversal,
    this.extractText,
    this.maxScreenshotSize = const Size(2000, 2000),
    this.logCollector,
  });

  /// Determines if an app-specific widget type is interactive.
  ///
  /// This is called only after checking built-in Flutter widgets.
  /// Return true for custom widgets that should be included
  /// in the interactive elements tree (e.g., custom buttons, text fields).
  final bool Function(Type type)? isInteractiveWidget;

  /// Determines if traversal should stop at an app-specific widget type.
  ///
  /// This is called only after checking built-in Flutter widgets.
  /// Return true for custom widgets that should stop tree traversal.
  final bool Function(Type type)? shouldStopTraversal;

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
  /// (Text, RichText, EditableText, TextField, TextFormField, Semantics).
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

  /// Checks if a widget type is interactive (built-in + custom).
  bool isInteractiveWidgetType(Type type) {
    return _isBuiltInInteractiveWidget(type) ||
        (isInteractiveWidget?.call(type) ?? false);
  }

  /// Returns whether traversal should stop at the given widget type.
  bool shouldStopAtType(Type type) {
    if (_isBuiltInStopWidget(type)) {
      return true;
    } else if (shouldStopTraversal != null) {
      return shouldStopTraversal!(type);
    } else {
      return false;
    }
  }

  /// Extracts text from a widget (built-in + custom).
  String? extractTextFromWidget(Element element) {
    final builtInText = _extractBuiltInText(element.widget);
    return builtInText ?? extractText?.call(element);
  }

  // Built-in Flutter widget support

  static bool _isBuiltInInteractiveWidget(Type type) {
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

  static bool _isBuiltInStopWidget(Type type) {
    return (type != GestureDetector && type != InkWell) &&
        (_isBuiltInInteractiveWidget(type) || type == Text);
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
    if (widget is Semantics) {
      // Surface explicit accessibility labels so agents can read content that
      // Flutter renders via inline-span trees (Text.rich, RichText with
      // composite spans, WidgetSpan content), custom-painted text, or
      // third-party markdown/rich-text packages — cases where toPlainText()
      // loses structure or returns nothing.
      //
      // Wrapping the visual widget in Semantics(label: '...') gives both
      // screen readers (VoiceOver/TalkBack) AND Marionette a clean string,
      // without changing rendering. Semantics widgets without an explicit
      // label or value are NOT reported, so framework-internal annotations
      // do not pollute the output.
      final label = widget.properties.label;
      if (label != null && label.isNotEmpty) return label;
      final value = widget.properties.value;
      if (value != null && value.isNotEmpty) return value;
      return null;
    }
    return null;
  }
}
