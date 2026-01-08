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
}
