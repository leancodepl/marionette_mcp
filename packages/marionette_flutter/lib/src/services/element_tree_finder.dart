import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';

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
    final text = configuration.extractTextFromWidget(widget);
    final keyValue = _extractKeyValue(widget.key);

    if (!isInteractive && text == null && keyValue == null) {
      return null;
    }

    final data = <String, dynamic>{'type': widget.runtimeType.toString()};

    if (keyValue != null) {
      data['key'] = keyValue;
    }

    if (text != null) {
      data['text'] = text;
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
        final screenSize =
            WidgetsBinding
                .instance
                .platformDispatcher
                .views
                .first
                .physicalSize /
            WidgetsBinding
                .instance
                .platformDispatcher
                .views
                .first
                .devicePixelRatio;

        final isOnScreen =
            offset.dx + size.width >= 0 &&
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
