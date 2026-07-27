import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Finds widgets in the Flutter widget tree using various matching criteria.
class WidgetFinder {
  /// Finds the first element that matches the given [matcher].
  ///
  /// Traverses the widget tree starting from the root element and returns
  /// the first element whose widget matches the provided matcher. When
  /// [ancestors] is given, only the subtree it resolves to is traversed.
  ///
  /// Returns null if no matching element is found.
  Element? findElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration, {
    List<KeyMatcher> ancestors = const [],
  }) {
    return findElementFrom(
      matcher,
      resolveScopeRoot(ancestors, configuration),
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
  /// When [ancestors] is given, only the subtree it resolves to is traversed.
  Element? findHittableElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration, {
    List<KeyMatcher> ancestors = const [],
  }) {
    return _findHittableElementFrom(
      matcher,
      resolveScopeRoot(ancestors, configuration),
      configuration,
    );
  }

  /// Resolves the element that an `ancestor_keys` chain limits a search to.
  ///
  /// [ancestors] is ordered outermost first and nests: each key is looked up
  /// inside the subtree of the one before it, so a chain can reach a subtree
  /// whose own key repeats elsewhere. An empty chain resolves to the app's
  /// root element.
  ///
  /// Throws when a link matches no element: falling back to a tree-wide search
  /// would silently act on a different subtree than the one that was asked
  /// for. The message names the link that broke and where it was looked for.
  Element? resolveScopeRoot(
    List<KeyMatcher> ancestors,
    MarionetteConfiguration configuration,
  ) {
    Element? scopeRoot = WidgetsBinding.instance.rootElement;

    for (var i = 0; i < ancestors.length; i++) {
      final found = findElementFrom(ancestors[i], scopeRoot, configuration);
      if (found == null) {
        final within = i == 0 ? '' : ' inside "${ancestors[i - 1].keyValue}"';
        throw Exception(
          'Scope element with key "${ancestors[i].keyValue}" '
          '(ancestor_keys[$i]) not found$within',
        );
      }
      scopeRoot = found;
    }

    return scopeRoot;
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
