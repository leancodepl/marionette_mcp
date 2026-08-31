import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';

/// Finds and extracts interactive elements from the Flutter widget tree.
class ElementTreeFinder {
  const ElementTreeFinder(this.configuration);

  final MarionetteConfiguration configuration;

  /// Returns a list of interactive elements from the current widget tree.
  ///
  /// When [compact] is true, the per-element property dump is reduced to
  /// primitive-valued properties only (see [_extractElementData]), dropping the
  /// large `ButtonStyle`/`TextStyle`/`InputDecoration` blobs that otherwise
  /// dominate the output.
  List<Map<String, dynamic>> findInteractiveElements({bool compact = false}) {
    final elements = <Map<String, dynamic>>[];
    final rootElement = WidgetsBinding.instance.rootElement;

    if (rootElement != null) {
      _visitElement(rootElement, elements, compact: compact);
    }

    return elements;
  }

  void _visitElement(
    Element element,
    List<Map<String, dynamic>> result, {
    required bool compact,
  }) {
    final widget = element.widget;
    final elementData = _extractElementData(element, widget, compact: compact);

    if (elementData != null) {
      result.add(elementData);
    }

    if (configuration.shouldStopAtType(widget.runtimeType)) {
      return;
    }

    element.visitChildren((child) {
      _visitElement(child, result, compact: compact);
    });
  }

  Map<String, dynamic>? _extractElementData(
    Element element,
    Widget widget, {
    required bool compact,
  }) {
    // Only process elements with render objects
    final renderObject = element.renderObject;
    if (renderObject == null) {
      return null;
    }

    // Check if this is an interactive or meaningful widget
    final isInteractive = configuration.isInteractiveWidgetType(
      widget.runtimeType,
    );
    final text = configuration.extractTextFromWidget(element);
    // Discovery-only Semantics fallback: if the standard matcher path yielded
    // no text, surface explicit accessibility annotations so agents can read
    // content rendered via inline-span trees, custom painters, or third-party
    // rich-text packages. Kept separate from extractTextFromWidget so that
    // TextMatcher (tap/scroll_to/enter_text) is not affected — otherwise a
    // Semantics(label: 'Save', child: ElevatedButton(...)) wrapper would
    // shadow the inner button.
    final discoverableText = text ?? _extractSemanticsText(widget);
    final keyValue = _extractKeyValue(widget.key);

    if (!isInteractive && discoverableText == null && keyValue == null) {
      return null;
    }

    // Only return widgets that can be hit
    if (!isElementHittable(element)) {
      return null;
    }

    final properties = DiagnosticPropertiesBuilder();
    widget.debugFillProperties(properties);
    // In compact mode keep only primitive-valued properties (bool/num/String/
    // Enum) and drop object blobs (ButtonStyle, TextStyle, InputDecoration,
    // Color, controllers, FocusNode) and callbacks/closures. Filtering by value
    // type — rather than by DiagnosticsNode subtype — is necessary because
    // widgets are inconsistent: e.g. TextField declares `enabled`/`obscureText`
    // as generic DiagnosticsProperty<bool> while ElevatedButton uses
    // FlagProperty. Exact retained fields therefore vary per widget.
    final data = Map<String, Object>.fromEntries(
      properties.properties
          .where((p) =>
              p.runtimeType != DiagnosticsProperty &&
              p.name != null &&
              p.value != null &&
              (!compact ||
                  (_isPrimitive(p.value) && !_isLayoutDetail(p.name!))))
          .map(
            (p) => MapEntry(p.name!, p.value.toString()),
          ),
    );

    data['type'] = widget.runtimeType.toString();

    if (keyValue != null) {
      data['key'] = keyValue;
    }

    if (discoverableText != null) {
      data['text'] = discoverableText;
      // `Text` also declares its string as `data`, so an element would carry
      // the same words twice.
      if (compact && data['data'] == discoverableText) {
        data.remove('data');
      }
    }

    // The InputDecoration blob is dropped in compact mode, but it carries a
    // keyless text field's only human-readable handle (its `text` holds the
    // entered value, empty for a blank field). Surface the label/hint so such
    // fields stay identifiable. TextFormField has no public `decoration`, so
    // this only applies to TextField.
    if (compact && widget is TextField) {
      final label = widget.decoration?.labelText ?? widget.decoration?.hintText;
      if (label != null && label.isNotEmpty) {
        data['label'] = label;
      }
    }

    // Get position and size if available
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        // Logical pixels, and the agent uses them to reason about position and
        // to tap by coordinate — neither needs the sixteen significant digits a
        // double prints (`411.42857142857144`). Rounded only in compact mode,
        // so the default payload stays byte-for-byte what it was.
        data['bounds'] = compact
            ? {
                'x': offset.dx.round(),
                'y': offset.dy.round(),
                'width': size.width.round(),
                'height': size.height.round(),
              }
            : {
                'x': offset.dx,
                'y': offset.dy,
                'width': size.width,
                'height': size.height,
              };
      } catch (_) {
        // Ignore if we can't get bounds
      }
    }

    // Check visibility. Every element in the list is on screen in the ordinary
    // case, so in compact mode this is reported only when it is not — absence
    // means visible, and the exception stays impossible to miss.
    final visible = _isElementVisible(renderObject);
    if (!compact || !visible) {
      data['visible'] = visible;
    }

    return data;
  }

  /// Whether [value] is a primitive worth keeping in compact mode.
  static bool _isPrimitive(Object? value) =>
      value is bool || value is num || value is String || value is Enum;

  /// Properties that survive the primitive filter but say nothing an agent can
  /// act on: they describe how text or gestures are laid out and rendered, and
  /// no interaction tool reads them (`tap`/`enter_text`/`scroll_to`/`swipe`
  /// match on key, text, type or coordinates). They are also the ones that
  /// dominate what is left once the object blobs are gone — every `Text` in a
  /// list carries five of them.
  static const _layoutDetails = {
    'startBehavior',
    'textAlign',
    'textDirection',
    'softWrap',
    'overflow',
    'textScaler',
    'textWidthBasis',
    'textHeightBehavior',
    'locale',
    'selectionColor',
  };

  static bool _isLayoutDetail(String name) => _layoutDetails.contains(name);

  String? _extractKeyValue(Key? key) {
    if (key is ValueKey<String>) {
      return key.value;
    }
    return null;
  }

  /// Discovery-only fallback: extracts the accessibility annotation from a
  /// `Semantics` widget.
  ///
  /// Combines `label` and `value` the way screen readers announce them
  /// (`'label: value'`) so widgets that set both — e.g.
  /// `Semantics(label: 'Volume', value: '70%')` — keep their dynamic state
  /// in the discovery output instead of dropping `value` when `label` is
  /// also present. Falls back to whichever field is non-empty when only one
  /// is set, and returns null when neither carries content.
  ///
  /// This is intentionally kept out of [MarionetteConfiguration.extractTextFromWidget]
  /// so that [TextMatcher] is not affected by Semantics wrappers — see the
  /// class-level dartdoc on `MarionetteConfiguration` for the rationale.
  static String? _extractSemanticsText(Widget widget) {
    if (widget is! Semantics) return null;
    final label = widget.properties.label;
    final value = widget.properties.value;
    final hasLabel = label != null && label.isNotEmpty;
    final hasValue = value != null && value.isNotEmpty;
    if (hasLabel && hasValue) return '$label: $value';
    if (hasLabel) return label;
    if (hasValue) return value;
    return null;
  }

  /// Checks if the element is currently visible on screen.
  bool _isElementVisible(RenderObject? renderObject) {
    if (renderObject == null || !renderObject.attached) {
      return false;
    }

    if (renderObject is RenderBox) {
      if (!renderObject.hasSize) {
        return false;
      }

      final size = renderObject.size;
      if (size.width <= 0 || size.height <= 0) {
        return false;
      }

      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final screenSize = WidgetsBinding
                .instance.platformDispatcher.views.first.physicalSize /
            WidgetsBinding
                .instance.platformDispatcher.views.first.devicePixelRatio;

        final isOnScreen = offset.dx + size.width >= 0 &&
            offset.dy + size.height >= 0 &&
            offset.dx < screenSize.width &&
            offset.dy < screenSize.height;

        return isOnScreen;
      } catch (_) {
        return true;
      }
    }

    return true;
  }
}
