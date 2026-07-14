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
  /// Finds the first [Scrollable] in the tree and scrolls it until the target
  /// widget becomes visible or max attempts are exhausted.
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
    final initialTarget = _widgetFinder.findElement(matcher, configuration);
    if (initialTarget != null) {
      final ancestorScrollable = _findScrollableAncestor(initialTarget);
      if (ancestorScrollable != null) {
        return ancestorScrollable;
      }
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return null;
    }

    // The target isn't built yet (e.g. it's off-screen in a lazily built
    // list), so it can't be found directly. Fall back to scanning the tree
    // for candidate Scrollables. A screen can have more than one — a
    // horizontal chip row or tab strip alongside the main vertical list, for
    // example — so instead of taking the first scrollable-with-range found
    // in traversal order (which can latch onto a small auxiliary
    // scrollable and then scroll the wrong axis entirely), collect every
    // candidate and prefer the one covering the most screen area: the main
    // scroll body is almost always larger than an auxiliary strip/carousel.
    Element? fallbackScrollable;
    Element? bestScrollableWithRange;
    var bestArea = -1.0;

    void visit(Element element) {
      if (element.widget is Scrollable) {
        fallbackScrollable ??= element;
        final position = _tryResolveScrollPosition(element);
        if (position != null && _hasScrollableRange(position)) {
          final area = _elementArea(element);
          if (area > bestArea) {
            bestArea = area;
            bestScrollableWithRange = element;
          }
        }
      }

      element.visitChildren(visit);
    }

    visit(root);
    return bestScrollableWithRange ?? fallbackScrollable;
  }

  double _elementArea(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return 0;
    }
    final size = renderObject.size;
    return size.width * size.height;
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
      // Find the target element
      final target = _widgetFinder.findElement(targetMatcher, configuration);
      // Check if target is visible
      if (target != null && isElementHittable(target)) {
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
