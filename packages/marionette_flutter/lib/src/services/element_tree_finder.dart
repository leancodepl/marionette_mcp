import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';

/// Finds and extracts interactive elements from the Flutter widget tree.
class ElementTreeFinder {
  const ElementTreeFinder(this.configuration);

  final MarionetteConfiguration configuration;

  /// Returns a list of interactive elements from the current widget tree.
  List<Map<String, dynamic>> findInteractiveElements() {
    final elements = <Map<String, dynamic>>[];
    final rootElement = WidgetsBinding.instance.rootElement;

    if (rootElement != null) {
      _visitElement(rootElement, elements);
    }

    return elements;
  }

  void _visitElement(Element element, List<Map<String, dynamic>> result) {
    final widget = element.widget;
    final elementData = _extractElementData(element, widget);

    if (elementData != null) {
      result.add(elementData);
    }

    if (configuration.shouldStopAtType(widget.runtimeType)) {
      return;
    }

    element.visitChildren((child) {
      _visitElement(child, result);
    });
  }

  Map<String, dynamic>? _extractElementData(Element element, Widget widget) {
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
    final data = Map<String, Object>.fromEntries(
      properties.properties
          .where((p) =>
              p.runtimeType != DiagnosticsProperty &&
              p.name != null &&
              p.value != null)
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
    }

    // Get position and size if available
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final offset = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        data['bounds'] = {
          'x': offset.dx,
          'y': offset.dy,
          'width': size.width,
          'height': size.height,
        };
      } catch (_) {
        // Ignore if we can't get bounds
      }
    }

    // Check visibility
    data['visible'] = _isElementVisible(renderObject);

    return data;
  }

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
