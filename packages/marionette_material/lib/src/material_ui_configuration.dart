import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// Adds Marionette support for the widgets of the `material_ui` library.
extension MaterialUiConfiguration on MarionetteConfiguration {
  /// Returns this configuration with the `material_ui` widget rules added.
  ///
  /// ```dart
  /// MarionetteBinding.ensureInitialized(
  ///   const MarionetteConfiguration().withMaterialUi(),
  /// );
  /// ```
  MarionetteConfiguration withMaterialUi() {
    return withAdditionalWidgetSupport(
      library: MarionetteUiLibrary.materialUi,
      isInteractiveElement: _isInteractive,
      shouldStopTraversalAtElement: _stopsTraversal,
      extractText: (_) => null,
      controlKind: _controlKind,
      extractFieldLabel: _extractFieldLabel,
    );
  }
}

/// The pass-through controls are left out of [_stopsTraversal]: they show
/// their content or selected value in a child that must stay listed and
/// tappable on its own.
bool _isInteractive(Element element) {
  return switch (element.widget) {
    InkWell() ||
    DropdownButton() ||
    DropdownButtonFormField() ||
    PopupMenuButton() ||
    RadioListTile() => true,
    _ => _stopsTraversal(element),
  };
}

bool _stopsTraversal(Element element) {
  return switch (element.widget) {
    ButtonStyleButton() ||
    IconButton() ||
    FloatingActionButton() ||
    Slider() ||
    Checkbox() ||
    CheckboxListTile() ||
    Radio() ||
    Switch() ||
    SwitchListTile() ||
    TextField() ||
    TextFormField() => true,
    _ => false,
  };
}

MarionetteControlKind? _controlKind(Element element) {
  return switch (element.widget) {
    TextField() || TextFormField() => MarionetteControlKind.textField,
    Checkbox() ||
    CheckboxListTile() ||
    Switch() ||
    SwitchListTile() => MarionetteControlKind.toggle,
    Radio() || RadioListTile() => MarionetteControlKind.radio,
    _ => null,
  };
}

/// The label or hint of a `TextField`, or of the `TextField` a
/// `TextFormField` builds, which has no public `decoration` of its own.
String? _extractFieldLabel(Element element) {
  final decoration = switch (element.widget) {
    TextField(:final decoration) => decoration,
    TextFormField() => _innerTextField(element)?.decoration,
    _ => null,
  };
  final label = decoration?.labelText ?? decoration?.hintText;
  return label == null || label.isEmpty ? null : label;
}

TextField? _innerTextField(Element element) {
  TextField? found;
  void visit(Element child) {
    if (found != null) return;
    if (child.widget case final TextField field) {
      found = field;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return found;
}
