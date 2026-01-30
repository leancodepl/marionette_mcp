import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    // Only return widgets that can be hit
    if (!_canBeHit(renderObject)) {
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

  /// Checks if the render object can be hit (receives pointer events).
  bool _canBeHit(RenderObject renderObject) {
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    if (!renderObject.attached) {
      return false;
    }

    try {
      final hitPoint = renderObject.localToGlobal(
        renderObject.size.center(Offset.zero),
      );

      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(
        result,
        hitPoint,
        WidgetsBinding.instance.platformDispatcher.views.first.viewId,
      );

      // Check if this render object is in the hit test path
      for (final entry in result.path) {
        if (entry.target == renderObject) {
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }
}
