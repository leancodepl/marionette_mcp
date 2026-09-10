import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
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
      } else if (matcher.matches(element, configuration)) {
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
  /// This should be used by tools that dispatch gestures (tap, enter_text) and
  /// by tools that ask whether the user can reach a widget (scroll_to), where
  /// matching a widget on a covered layer would result in a silent failure.
  /// Use [findElement] where a match the user cannot currently reach is still
  /// a valid answer.
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
      } else if (matcher.matches(element, configuration) &&
          isElementHittable(element)) {
        found = element;
      } else {
        element.visitChildren(visitor);
      }
    }

    visitor(startElement);
    return found;
  }
}
