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
    // Keep this convenience API for existing callers, but delegate to the
    // "find all" traversal so there is a single matching implementation.
    final elements = findElementsFrom(matcher, startElement, configuration);
    return elements.isEmpty ? null : elements.first;
  }

  /// Finds all elements that match [matcher] within [startElement]'s subtree.
  List<Element> findElementsFrom(
    WidgetMatcher matcher,
    Element? startElement,
    MarionetteConfiguration configuration,
  ) {
    if (startElement == null) {
      return const [];
    }

    final found = <Element>[];

    void visitor(Element element) {
      // DFS order is important: it preserves historical "first match wins"
      // semantics for callers that still consume only the first match.
      if (matcher.matches(element.widget, configuration)) {
        found.add(element);
      }
      // Even if this element matches, continue traversing. Some workflows need
      // all candidates to apply additional runtime filters.
      element.visitChildren(visitor);
    }

    visitor(startElement);
    return found;
  }

  /// Finds all matching elements in DFS order from the root tree.
  List<Element> findElements(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    return findElementsFrom(
      matcher,
      WidgetsBinding.instance.rootElement,
      configuration,
    );
  }
}
