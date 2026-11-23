import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// Adds Marionette support for the widgets of the `cupertino_ui` library.
extension CupertinoUiConfiguration on MarionetteConfiguration {
  /// Returns this configuration with the `cupertino_ui` widget rules added.
  ///
  /// ```dart
  /// MarionetteBinding.ensureInitialized(
  ///   const MarionetteConfiguration().withCupertinoUi(),
  /// );
  /// ```
  MarionetteConfiguration withCupertinoUi() {
    return withAdditionalWidgetSupport(
      library: MarionetteUiLibrary.cupertinoUi,
      isInteractiveElement: _isInteractive,
      shouldStopTraversalAtElement: _stopsTraversal,
      extractText: (_) => null,
      controlKind: _controlKind,
      extractFieldLabel: _extractPlaceholder,
    );
  }
}

bool _isInteractive(Element element) {
  return switch (element.widget) {
    CupertinoSegmentedControl() || CupertinoSlidingSegmentedControl() => true,
    _ => _stopsTraversal(element),
  };
}

/// The segmented controls are left out: each segment shows its label in a
/// child that must stay listed and tappable on its own.
bool _stopsTraversal(Element element) {
  return switch (element.widget) {
    CupertinoButton() ||
    CupertinoTextField() ||
    CupertinoSearchTextField() ||
    CupertinoCheckbox() ||
    CupertinoRadio() ||
    CupertinoSwitch() ||
    CupertinoSlider() => true,
    _ => false,
  };
}

MarionetteControlKind? _controlKind(Element element) {
  return switch (element.widget) {
    CupertinoTextField() ||
    CupertinoSearchTextField() => MarionetteControlKind.textField,
    CupertinoCheckbox() || CupertinoSwitch() => MarionetteControlKind.toggle,
    CupertinoRadio() => MarionetteControlKind.radio,
    _ => null,
  };
}

/// The placeholder of a `CupertinoTextField`, or of the one a
/// `CupertinoSearchTextField` builds, which holds the localized default when
/// the app sets none; null for anything else.
String? _extractPlaceholder(Element element) {
  final placeholder = switch (element.widget) {
    CupertinoTextField(:final placeholder) => placeholder,
    CupertinoSearchTextField() => _innerTextField(element)?.placeholder,
    _ => null,
  };
  return placeholder == null || placeholder.isEmpty ? null : placeholder;
}

/// The first `CupertinoTextField` below [element].
CupertinoTextField? _innerTextField(Element element) {
  CupertinoTextField? field;
  void visit(Element child) {
    if (field != null) return;
    if (child.widget case final CupertinoTextField inner) {
      field = inner;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return field;
}
