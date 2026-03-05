import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Matched element paired with its nearest scrollable ancestor.
class WidgetMatchCandidate {
  const WidgetMatchCandidate({
    required this.element,
    required this.scrollableAncestor,
  });

  final Element element;
  final Element? scrollableAncestor;
}

/// Resolves match candidates into interaction-ready elements.
///
/// This centralizes the operations used by tap/enter_text/scroll_to:
/// collecting candidates, checking hittability, and associating matches
/// with scroll context.
class ElementResolver {
  const ElementResolver(this._widgetFinder);

  final WidgetFinder _widgetFinder;

  /// Finds every matcher hit and pairs each hit with the nearest Scrollable
  /// ancestor.
  ///
  /// The returned list keeps DFS match order from [WidgetFinder], but each
  /// entry now includes:
  /// - the matched element itself
  /// - the closest scrollable container that can move that element (if any)
  ///
  /// This gives callers enough context to make tool-specific decisions without
  /// re-traversing the tree.
  List<WidgetMatchCandidate> findCandidates(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    // Build this "match + nearest scrollable" list in one place so tap,
    // enter_text, and scroll_to all start from the same data.
    // Each tool then applies its own acceptance rule on top of that list.
    final elements = _widgetFinder.findElements(matcher, configuration);
    return elements
        .map(
          (element) => WidgetMatchCandidate(
            element: element,
            scrollableAncestor: findScrollableAncestor(element),
          ),
        )
        .toList(growable: false);
  }

  /// Finds the first matching element that can receive pointer events.
  Element? findHittableElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    final candidates = findCandidates(matcher, configuration);
    for (final candidate in candidates) {
      // This rejects matches hidden behind modal barriers, absorb/ignore
      // pointer layers, and other non-hit-testable widgets.
      if (isHittable(candidate.element)) {
        return candidate.element;
      }
    }
    return null;
  }

  /// Finds the first match inside a scrollable that can currently receive
  /// pointer input.
  WidgetMatchCandidate? findCandidateInHittableScrollable(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    final candidates = findCandidates(matcher, configuration);
    for (final candidate in candidates) {
      final scrollable = candidate.scrollableAncestor;
      // scroll_to must be able to target offscreen widgets, so we do NOT
      // require the target element itself to be hittable yet. Instead we
      // require the containing scrollable layer to be currently interactable.
      if (scrollable != null && isHittable(scrollable)) {
        return candidate;
      }
    }
    return null;
  }

  /// Finds the nearest [Scrollable] ancestor of [element], if any.
  Element? findScrollableAncestor(Element element) {
    Element? scrollableAncestor;
    element.visitAncestorElements((Element ancestor) {
      if (ancestor.widget is Scrollable) {
        // Nearest ancestor wins: this is the scroll container that can
        // actually move the matched widget into view.
        scrollableAncestor = ancestor;
        return false;
      }
      return true;
    });
    return scrollableAncestor;
  }

  /// Checks if the element can receive pointer events.
  static bool isHittable(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      // Without a sized RenderBox, there is no stable point to hit-test.
      return false;
    }

    if (!renderObject.attached) {
      // Detached objects are stale and cannot receive pointer events.
      return false;
    }

    final view = element.findAncestorWidgetOfExactType<View>();
    final viewId = view?.view.viewId ??
        WidgetsBinding.instance.platformDispatcher.implicitView?.viewId;
    if (viewId == null) {
      // No view means no hit-test target surface.
      return false;
    }

    try {
      // Use the visual center as a pragmatic probe point. This mirrors how
      // interactive elements are filtered elsewhere in Marionette.
      final center = renderObject.size.center(Offset.zero);
      final absoluteOffset = renderObject.localToGlobal(center);

      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, absoluteOffset, viewId);

      // The render object must appear in the hit-test path at that point.
      for (final entry in result.path) {
        if (entry.target == renderObject) {
          return true;
        }
      }

      return false;
    } catch (_) {
      // Geometry queries can throw during transient layout/paint phases.
      // Treat this as not hittable and let caller retry later.
      return false;
    }
  }
}
