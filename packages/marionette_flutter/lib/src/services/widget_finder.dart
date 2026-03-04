import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Finds widgets in the Flutter widget tree using various matching criteria.
class WidgetFinder {
  /// Finds the first element that matches the given [matcher].
  ///
  /// Traverses the widget tree starting from the root element and returns
  /// the first element whose widget matches the provided matcher.
  ///
  /// Returns null if no matching element is found.
  Element? findElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    return findElementFrom(
      matcher,
      WidgetsBinding.instance.rootElement,
      configuration,
    );
  }

  /// Finds the first element that matches the given [matcher] within the subtree
  /// rooted at the given [startElement].
  ///
  /// Returns null if no matching element is found.
  Element? findElementFrom(
    WidgetMatcher matcher,
    Element? startElement,
    MarionetteConfiguration configuration,
  ) {
    if (startElement == null) {
      return null;
    }

    Element? found;

    void visitor(Element element) {
      if (found != null) {
        return;
      } else if (matcher.matches(element.widget, configuration)) {
        found = element;
      } else {
        element.visitChildren(visitor);
      }
    }

    visitor(startElement);
    return found;
  }

  /// Finds the first element that matches the given [matcher] and is hittable
  /// (i.e. can receive pointer events and is not behind a modal barrier).
  ///
  /// This should be used by tools that dispatch gestures (tap, enter_text)
  /// where matching a non-hittable widget would result in a silent failure.
  /// Tools that need to find offscreen elements (e.g. scroll_to) should use
  /// [findElement] instead.
  Element? findHittableElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    return _findHittableElementFrom(
      matcher,
      WidgetsBinding.instance.rootElement,
      configuration,
    );
  }

  Element? _findHittableElementFrom(
    WidgetMatcher matcher,
    Element? startElement,
    MarionetteConfiguration configuration,
  ) {
    if (startElement == null) {
      return null;
    }

    Element? found;

    void visitor(Element element) {
      if (found != null) {
        return;
      } else if (matcher.matches(element.widget, configuration) &&
          isHittable(element)) {
        found = element;
      } else {
        element.visitChildren(visitor);
      }
    }

    visitor(startElement);
    return found;
  }

  /// Checks if the element can receive pointer events.
  ///
  /// Performs a hit test at the center of the element and checks whether its
  /// render object appears in the hit test path. Elements behind modal
  /// barriers, [AbsorbPointer], [IgnorePointer], or offscreen will return
  /// false.
  static bool isHittable(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    if (!renderObject.attached) {
      return false;
    }

    final view = element.findAncestorWidgetOfExactType<View>();
    final viewId = view?.view.viewId ??
        WidgetsBinding.instance.platformDispatcher.implicitView?.viewId;
    if (viewId == null) {
      return false;
    }

    try {
      final center = renderObject.size.center(Offset.zero);
      final absoluteOffset = renderObject.localToGlobal(center);

      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, absoluteOffset, viewId);

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
