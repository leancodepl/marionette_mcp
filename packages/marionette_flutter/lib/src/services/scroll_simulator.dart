import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Simulates scrolling gestures to make widgets visible.
class ScrollSimulator {
  const ScrollSimulator(this._gestureDispatcher, this._widgetFinder);

  final GestureDispatcher _gestureDispatcher;
  final WidgetFinder _widgetFinder;

  static const _delta = 64.0;
  static const _fallbackMaxScrollAttempts = 50;
  static const _defaultMaxScrollAttemptsCap = 200;
  static const _attemptPadding = 20;
  static const _positionEpsilon = 0.5;
  static const _stallAttemptsBeforeReverse = 2;

  /// Scrolls until the widget matching [matcher] is visible.
  ///
  /// Picks the [Scrollable] the user can currently reach rather than the first
  /// one in the tree — a covered layer stays built and comes earlier — and
  /// drags it until the target becomes reachable or max attempts are
  /// exhausted.
  ///
  /// Throws an [Exception] if:
  /// - The target widget is not found
  /// - No [Scrollable] widget is found in the tree
  /// - The target widget is not visible after all attempts are exhausted
  Future<void> scrollUntilVisible(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) async {
    final scrollable = _findScrollableElement(matcher, configuration);
    if (scrollable == null) {
      throw Exception('No Scrollable widget found in the tree');
    }

    // Get the scroll direction
    final scrollableWidget = scrollable.widget as Scrollable;
    final direction = scrollableWidget.axisDirection;
    final position = _resolveScrollPosition(scrollable);

    // Calculate move step based on direction
    final initialMoveStep = switch (direction) {
      AxisDirection.up => const Offset(0, _delta),
      AxisDirection.down => const Offset(0, -_delta),
      AxisDirection.left => const Offset(_delta, 0),
      AxisDirection.right => const Offset(-_delta, 0),
    };
    final maxScrollAttempts = _calculateMaxScrollAttempts(position);

    // Scroll until visible
    await _dragUntilVisible(
      matcher,
      scrollable,
      position,
      initialMoveStep,
      maxScrollAttempts,
      configuration,
    );
  }

  Element? _findScrollableElement(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return null;
    }

    final targetScrollable = _findScrollableOwningAMatch(
      matcher,
      root,
      configuration,
    );
    if (targetScrollable != null) {
      return targetScrollable;
    }

    // The target is not in the tree yet, which is normal for lazily built
    // lists. Fall back to picking a Scrollable, preferring ones the user can
    // currently reach so a covered layer does not win just by being first.
    Element? fallbackScrollable;
    Element? scrollableWithRange;
    Element? reachableFallback;
    Element? reachableWithRange;

    void visit(Element element) {
      if (reachableWithRange != null) {
        return;
      }

      if (element.widget is Scrollable) {
        final position = _tryResolveScrollPosition(element);
        final hasRange = position != null && _hasScrollableRange(position);

        fallbackScrollable ??= element;
        if (hasRange) {
          scrollableWithRange ??= element;
        }

        if (isElementHittable(element)) {
          reachableFallback ??= element;
          if (hasRange) {
            reachableWithRange ??= element;
            return;
          }
        }
      }

      element.visitChildren(visit);
    }

    visit(root);

    // Most to least preferred. Reachability outranks scroll range because the
    // drag starts at the centre of the chosen Scrollable, the exact point
    // hittability is measured at: one that fails the check cannot be dragged
    // at all, range or no range. The last two tiers keep the previous
    // behaviour for trees where hittability is never established.
    return reachableWithRange ??
        reachableFallback ??
        scrollableWithRange ??
        fallbackScrollable;
  }

  /// Returns the [Scrollable] containing a match that the user can reach.
  ///
  /// Every match is considered, not just the first, because a covered layer
  /// sits earlier in the element tree than the one on top. The match itself
  /// does not need to be hittable — it may still be scrolled out of view — so
  /// reachability is judged on the [Scrollable] that would move it.
  Element? _findScrollableOwningAMatch(
    WidgetMatcher matcher,
    Element root,
    MarionetteConfiguration configuration,
  ) {
    Element? firstScrollable;
    Element? reachableScrollable;

    void visit(Element element) {
      if (reachableScrollable != null) {
        return;
      }

      if (matcher.matches(element, configuration)) {
        final scrollable = _findScrollableAncestor(element);
        if (scrollable != null) {
          firstScrollable ??= scrollable;
          if (isElementHittable(scrollable)) {
            reachableScrollable = scrollable;
            return;
          }
        }
      }

      element.visitChildren(visit);
    }

    visit(root);
    return reachableScrollable ?? firstScrollable;
  }

  Element? _findScrollableAncestor(Element element) {
    Element? scrollableAncestor;
    element.visitAncestorElements((Element ancestor) {
      if (ancestor.widget is Scrollable) {
        scrollableAncestor = ancestor;
        return false;
      }
      return true;
    });
    return scrollableAncestor;
  }

  /// Repeatedly drags the scrollable until the target is visible.
  Future<void> _dragUntilVisible(
    WidgetMatcher targetMatcher,
    Element scrollable,
    ScrollPosition position,
    Offset initialMoveStep,
    int maxScrollAttempts,
    MarionetteConfiguration configuration,
  ) async {
    var moveStep = initialMoveStep;
    var searchingTowardEnd = true;
    var hasReversedDirection = false;
    var stalledAttempts = 0;

    for (var i = 0; i < maxScrollAttempts; i++) {
      // Look for a match that can actually receive pointer events. Matching on
      // the first hit alone is not enough: a covered layer is earlier in the
      // tree, so a widget the user cannot reach would mask the one they can.
      final target = _widgetFinder.findHittableElement(
        targetMatcher,
        configuration,
      );
      if (target != null) {
        return;
      }

      final atCurrentEdgeBeforeDrag = searchingTowardEnd
          ? position.extentAfter <= _positionEpsilon
          : position.extentBefore <= _positionEpsilon;
      if (atCurrentEdgeBeforeDrag) {
        if (!hasReversedDirection) {
          hasReversedDirection = true;
          searchingTowardEnd = false;
          moveStep = -moveStep;
          stalledAttempts = 0;
          continue;
        }
        break;
      }

      final renderObject = scrollable.renderObject;
      if (renderObject is! RenderBox) {
        throw Exception('Scrollable does not have a RenderBox');
      }

      final center = renderObject.size.center(Offset.zero);
      final globalPosition = renderObject.localToGlobal(center);

      final to = globalPosition + moveStep;
      final beforePosition = position.pixels;
      await _gestureDispatcher.drag(globalPosition, to);

      final afterPosition = position.pixels;
      final moved = (afterPosition - beforePosition).abs() > _positionEpsilon;
      final atCurrentEdgeAfterDrag = searchingTowardEnd
          ? position.extentAfter <= _positionEpsilon
          : position.extentBefore <= _positionEpsilon;

      if (atCurrentEdgeAfterDrag) {
        if (!hasReversedDirection) {
          hasReversedDirection = true;
          searchingTowardEnd = false;
          moveStep = -moveStep;
          stalledAttempts = 0;
          continue;
        }
        break;
      }

      if (moved) {
        stalledAttempts = 0;
        continue;
      }

      stalledAttempts++;
      if (stalledAttempts < _stallAttemptsBeforeReverse) {
        continue;
      }

      if (!hasReversedDirection) {
        // We likely hit the edge in the current direction. Reverse once and
        // scan the opposite side of the list.
        hasReversedDirection = true;
        moveStep = -moveStep;
        stalledAttempts = 0;
        continue;
      }

      break;
    }

    // The loop checks for the target on entry but leaves from the middle, so
    // the position the last drag landed on has not been examined yet. Look
    // once more before giving up: the target may be sitting on screen.
    if (_widgetFinder.findHittableElement(targetMatcher, configuration) !=
        null) {
      return;
    }

    // Target still not visible after max scrolls
    throw StateError(
      'Widget not found after $maxScrollAttempts scroll attempts',
    );
  }

  ScrollPosition _resolveScrollPosition(Element scrollable) {
    final position = _tryResolveScrollPosition(scrollable);
    if (position == null) {
      throw Exception('Scrollable element does not expose ScrollableState');
    }
    return position;
  }

  ScrollPosition? _tryResolveScrollPosition(Element scrollable) {
    if (scrollable is! StatefulElement) {
      return null;
    }
    final state = scrollable.state;
    if (state is! ScrollableState) {
      return null;
    }
    return state.position;
  }

  bool _hasScrollableRange(ScrollPosition position) {
    return (position.maxScrollExtent - position.minScrollExtent).abs() >
        _positionEpsilon;
  }

  int _calculateMaxScrollAttempts(ScrollPosition position) {
    final scrollExtent =
        (position.maxScrollExtent - position.minScrollExtent).abs();
    if (!scrollExtent.isFinite) {
      return _fallbackMaxScrollAttempts
          .clamp(1, _defaultMaxScrollAttemptsCap)
          .toInt();
    }

    final oneWayAttempts = (scrollExtent / _delta).ceil();

    // Allow one full pass in one direction and another after reverse,
    // with a small buffer for viewport alignment near edges.
    final adaptiveAttempts = oneWayAttempts * 2 + _attemptPadding;
    return adaptiveAttempts.clamp(1, _defaultMaxScrollAttemptsCap).toInt();
  }
}
