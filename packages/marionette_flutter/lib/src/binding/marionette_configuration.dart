import 'package:flutter/material.dart';

/// Configuration for the Marionette extensions.
///
/// Provides support for custom app-specific widgets.
/// Standard Flutter widgets (TextField, Button, Text, etc.) are supported by default.
class MarionetteConfiguration {
  const MarionetteConfiguration({
    this.isInteractiveWidget,
    this.shouldStopTraversal,
    this.extractText,
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
  /// This is called only after checking built-in Flutter widgets.
  /// Return the text content of your custom widgets, or null if not applicable.
  final String? Function(Widget widget)? extractText;

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
  String? extractTextFromWidget(Widget widget) {
    final builtInText = _extractBuiltInText(widget);
    return builtInText ?? extractText?.call(widget);
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
    return null;
  }
}
