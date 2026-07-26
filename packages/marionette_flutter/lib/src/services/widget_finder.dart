import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Finds widgets in the Flutter widget tree using various matching criteria.
class WidgetFinder {
  /// Finds the first element that matches the given [matcher].
  ///
  /// Traverses the widget tree starting from the root element and returns
  /// the first element whose widget matches the provided matcher. When [scope]
  /// is given, only the subtree of the element it matches is traversed.
  ///
  /// Returns null if no matching element is found.
  Element? findElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration, {
    KeyMatcher? scope,
  }) {
    return findElementFrom(
      matcher,
      resolveScopeRoot(scope, configuration),
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
  /// This should be used by tools that dispatch gestures (tap, enter_text)
  /// where matching a non-hittable widget would result in a silent failure.
  /// Tools that need to find offscreen elements (e.g. scroll_to) should use
  /// [findElement] instead.
  ///
  /// When [scope] is given, only the subtree of the element it matches is
  /// traversed.
  Element? findHittableElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration, {
    KeyMatcher? scope,
  }) {
    return _findHittableElementFrom(
      matcher,
      resolveScopeRoot(scope, configuration),
      configuration,
    );
  }

  /// Resolves the element that a `within_key` [scope] limits a search to.
  ///
  /// Returns the app's root element when [scope] is null.
  ///
  /// Throws when [scope] is given but matches no element: falling back to a
  /// tree-wide search would silently act on a different subtree than the one
  /// that was asked for.
  Element? resolveScopeRoot(
    KeyMatcher? scope,
    MarionetteConfiguration configuration,
  ) {
    final root = WidgetsBinding.instance.rootElement;
    if (scope == null) {
      return root;
    }

    final scopeElement = findElementFrom(scope, root, configuration);
    if (scopeElement == null) {
      throw Exception(
        'Scope element with key "${scope.keyValue}" (within_key) not found',
      );
    }
    return scopeElement;
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
