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

  static const _minDelta = 64.0;

  // Two, and no more, because of the caps below: one candidate may spend
  // _defaultMaxScrollAttemptsCap attempts and the whole call may spend
  // _totalScrollAttemptsCap, so two is the most that can each be given a full
  // budget. A third would get only what the first two left over, which is too
  // little to cross the list it was picked for.
  static const _maxScrollableCandidates = 2;
  static const _totalScrollAttemptsCap = 400;
  static const _exposureSamples = 21;
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
  /// When [ancestors] is given, the target is searched for inside that subtree
  /// only. The scope is resolved again on every lookup, because in a lazily
  /// built list it may not exist until the list scrolls to it. The
  /// [Scrollable] to drag is looked for inside the deepest resolvable scope
  /// first and then directly above it, since a scope may contain the list or
  /// sit inside it.
  ///
  /// Throws an [Exception] if:
  /// - The target widget is not found
  /// - No [Scrollable] widget is found in the tree
  /// - The target widget is not visible after all attempts are exhausted
  ///
  /// When the scope never resolved during the call, the
  /// [ScopeNotFoundException] naming the missing key is thrown instead of any
  /// of those: it is the more precise reason.
  Future<void> scrollUntilVisible(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration, {
    List<KeyMatcher> ancestors = const [],
  }) async {
    // Whether the scope resolved at any point, not whether it does at the end:
    // after a miss the scroll position is restored, which can unbuild a scope
    // that was found, and a missing target must not read as a missing scope.
    var scopeSeen = false;
    ScopeNotFoundException? lastMissingScope;

    Element? findTarget() {
      try {
        final target = _widgetFinder.findHittableElement(
          matcher,
          configuration,
          ancestors: ancestors,
        );
        scopeSeen = true;
        return target;
      } on ScopeNotFoundException catch (e) {
        // Not built yet, most likely: keep scrolling.
        lastMissingScope = e;
        return null;
      }
    }

    Never fail(Object error) {
      if (!scopeSeen) {
        final missing = lastMissingScope ??
            _widgetFinder.tryResolveScope(ancestors, configuration).missing;
        if (missing != null) {
          throw missing;
        }
      }
      throw error;
    }

    final candidates =
        _findScrollableCandidates(matcher, configuration, ancestors);
    if (candidates.isEmpty) {
      fail(Exception('No Scrollable widget found in the tree'));
    }

    var attemptsLeft = _totalScrollAttemptsCap;
    var draggedSomething = false;

    for (final candidate in candidates) {
      if (attemptsLeft <= 0) {
        break;
      }

      // Re-resolve rather than trusting what the ranking pass saw. Scrolling
      // one candidate builds and unbuilds widgets, and a Scrollable that has
      // gone away since takes its ScrollPosition with it.
      final position = _tryResolveScrollPosition(candidate);
      if (position == null) {
        continue;
      }

      final direction = (candidate.widget as Scrollable).axisDirection;
      final delta = _stepFor(candidate, direction);
      final initialMoveStep = switch (direction) {
        AxisDirection.up => Offset(0, delta),
        AxisDirection.down => Offset(0, -delta),
        AxisDirection.left => Offset(delta, 0),
        AxisDirection.right => Offset(-delta, 0),
      };
      final budget = _calculateMaxScrollAttempts(
        position,
        delta,
      ).clamp(1, attemptsLeft);
      final startedAt = position.pixels;

      final outcome = await _dragUntilVisible(
        findTarget,
        candidate,
        position,
        initialMoveStep,
        budget,
      );
      attemptsLeft -= outcome.attempts;
      draggedSomething |= outcome.attempts > 0;

      if (outcome.found) {
        return;
      }

      // Wrong guess. Put it back, so the only lasting effect of a scroll_to is
      // the scrolling that actually found the target.
      _restoreScrollPosition(candidate, startedAt);
    }

    if (!draggedSomething) {
      // Nothing ever moved, so an attempt count names the count rather than
      // the cause: every candidate either had nowhere to go or was gone by the
      // time its turn came.
      fail(
        StateError(
          'Widget not found: no Scrollable could be scrolled to reveal it',
        ),
      );
    }

    fail(
      StateError(
        'Widget not found after '
        '${_totalScrollAttemptsCap - attemptsLeft} scroll attempts',
      ),
    );
  }

  /// The [Scrollable]s worth dragging to reveal [matcher], best guess first.
  ///
  /// A built match settles the question outright — whatever encloses it is
  /// what moves it — but only when the user can reach that [Scrollable]. A
  /// covered layer stays built and comes first in the element tree, so the
  /// only match on screen may well be one nobody can touch.
  ///
  /// Without a reachable match the target simply is not built yet, which is
  /// ordinary for a lazily built list, and nothing in the tree says which
  /// [Scrollable] would eventually build it. Every ranking is a guess that
  /// some layout defeats, so rank the plausible ones and let the caller try
  /// them in turn: whether the target shows up is the only reliable signal.
  ///
  /// With [ancestors], the target is only looked for inside the scope, but the
  /// [Scrollable] that moves it may sit inside the scope (a list in a cell) or
  /// above it (a row of a list, a section of a long page). So the ranking
  /// starts from the deepest link of the chain that is built right now and
  /// takes the best [Scrollable] inside it, then the nearest one above it.
  /// Only when not even the first link is built does it fall back to the
  /// whole tree, as without a scope.
  List<Element> _findScrollableCandidates(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
    List<KeyMatcher> ancestors,
  ) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return const <Element>[];
    }

    final scope = _widgetFinder.tryResolveScope(ancestors, configuration);
    final anchor = scope.element ?? root;
    final scoped = ancestors.isNotEmpty;

    Element? unreachableOwner;
    if (scope.missing == null) {
      // The target, if built, is below the scope, never the scope itself.
      final owners = _findScrollablesOwningAMatch(
        matcher,
        anchor,
        configuration,
        includeRoot: !scoped,
      );
      final reachableOwner = owners.reachable;
      if (reachableOwner != null) {
        return <Element>[reachableOwner];
      }
      unreachableOwner = owners.first;
    }

    if (scoped && !identical(anchor, root)) {
      return _scrollablesAroundScope(anchor, unreachableOwner);
    }

    final ranked = _rankScrollables(root);
    final candidates = ranked.reachable;
    if (candidates.isEmpty) {
      // Nothing on screen answers a hit test, so reachability cannot rank
      // anything here. Keep the older single-pick behaviour rather than
      // refuse to scroll at all.
      final fallback =
          unreachableOwner ?? ranked.withRange ?? ranked.anyScrollable;
      if (fallback != null) {
        candidates.add(fallback);
      }
    }

    return candidates.take(_maxScrollableCandidates).toList();
  }

  /// The best [Scrollable] inside [scope], then the nearest one above it.
  ///
  /// Both are plausible and only dragging tells them apart, so each gets one
  /// of the candidate slots. One above that the user cannot reach goes last,
  /// since a drag from its centre would land on whatever covers it.
  List<Element> _scrollablesAroundScope(
    Element scope,
    Element? unreachableOwner,
  ) {
    final inside = _rankScrollables(scope);
    final above = _findScrollableAncestor(scope);
    final aboveReachable = above != null && isElementHittable(above);

    final candidates = <Element>[
      if (inside.reachable.isNotEmpty) inside.reachable.first,
      if (aboveReachable) above,
      ...inside.reachable.skip(1),
    ];
    if (candidates.isEmpty) {
      final fallback = unreachableOwner ?? inside.withRange;
      if (fallback != null) {
        candidates.add(fallback);
      }
    }
    if (above != null && !aboveReachable) {
      candidates.add(above);
    }

    return candidates.take(_maxScrollableCandidates).toList();
  }

  /// Every [Scrollable] at or below [root], ranked for dragging.
  ///
  /// [reachable] holds the ones the user can reach, best guess first;
  /// [withRange] and [anyScrollable] are the first unreachable fallbacks.
  ({List<Element> reachable, Element? withRange, Element? anyScrollable})
      _rankScrollables(Element root) {
    final reachableWithRange = <Element>[];
    final reachableWithoutRange = <Element>[];
    Element? scrollableWithRange;
    Element? anyScrollable;

    void visit(Element element) {
      if (element.widget is Scrollable) {
        final position = _tryResolveScrollPosition(element);
        final hasRange = position != null && _hasScrollableRange(position);

        anyScrollable ??= element;
        if (hasRange) {
          scrollableWithRange ??= element;
        }

        if (isElementHittable(element)) {
          (hasRange ? reachableWithRange : reachableWithoutRange).add(element);
        }
      }

      element.visitChildren(visit);
    }

    visit(root);

    // Reachable before out of reach, and with somewhere to go before without:
    // the drag starts at the centre of the chosen Scrollable, the exact point
    // hittability is measured at, so one that fails the check cannot be
    // dragged at all.
    //
    // Biggest first within a tier. A chip row, a tab strip or a carousel is
    // nearly always smaller than the body it decorates, so that is the better
    // guess to spend the first attempt on — but it is only an ordering, and
    // guessing wrong now costs an attempt rather than the whole call.
    _sortByAreaDescending(reachableWithRange);
    _sortByAreaDescending(reachableWithoutRange);

    return (
      reachable: <Element>[...reachableWithRange, ...reachableWithoutRange],
      withRange: scrollableWithRange,
      anyScrollable: anyScrollable,
    );
  }

  void _sortByAreaDescending(List<Element> elements) {
    elements.sort(
        (Element a, Element b) => _elementArea(b).compareTo(_elementArea(a)));
  }

  double _elementArea(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return 0;
    }
    final size = renderObject.size;
    return size.width * size.height;
  }

  void _restoreScrollPosition(Element scrollable, double pixels) {
    final position = _tryResolveScrollPosition(scrollable);
    if (position == null || !position.hasPixels) {
      return;
    }
    if ((position.pixels - pixels).abs() <= _positionEpsilon) {
      return;
    }
    position.jumpTo(pixels);
  }

  /// The [Scrollable]s containing a match: the first one found, and the first
  /// one the user can reach.
  ///
  /// Every match is considered, not just the first, because a covered layer
  /// sits earlier in the element tree than the one on top. The match itself
  /// does not need to be hittable — it may still be scrolled out of view — so
  /// reachability is judged on the [Scrollable] that would move it.
  ///
  /// The two are reported apart because they mean different things. A
  /// reachable owner is an answer. An unreachable one is a leftover from a
  /// covered layer, worth keeping only as a last resort: treating it as an
  /// answer is what made a sheet opened over a page with a same-named widget
  /// drag the page instead.
  ({Element? first, Element? reachable}) _findScrollablesOwningAMatch(
    WidgetMatcher matcher,
    Element root,
    MarionetteConfiguration configuration, {
    bool includeRoot = true,
  }) {
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

    if (includeRoot) {
      visit(root);
    } else {
      root.visitChildren(visit);
    }
    return (first: firstScrollable, reachable: reachableScrollable);
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
  ///
  /// Reports whether the target turned up and how many drags it took, so the
  /// caller can move on to the next candidate and keep a lid on the total.
  Future<_DragOutcome> _dragUntilVisible(
    Element? Function() findTarget,
    Element scrollable,
    ScrollPosition position,
    Offset initialMoveStep,
    int maxScrollAttempts,
  ) async {
    var moveStep = initialMoveStep;
    var searchingTowardEnd = true;
    var hasReversedDirection = false;
    var stalledAttempts = 0;
    var drags = 0;

    for (var i = 0; i < maxScrollAttempts; i++) {
      // Look for a match that can actually receive pointer events. Matching on
      // the first hit alone is not enough: a covered layer is earlier in the
      // tree, so a widget the user cannot reach would mask the one they can.
      final target = findTarget();
      if (target != null) {
        return _DragOutcome(found: true, attempts: drags);
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
        // Total for the same reason _tryResolveScrollPosition is: a candidate
        // can lose its layout while the loop is running, so reaching for what
        // is left has to read as a miss rather than a crash. Give this one up
        // and let the caller carry on to the next.
        break;
      }

      final center = renderObject.size.center(Offset.zero);
      final globalPosition = renderObject.localToGlobal(center);

      final to = globalPosition + moveStep;
      final beforePosition = position.pixels;
      await _gestureDispatcher.drag(
        globalPosition,
        to,
        viewId: viewIdOf(scrollable),
      );
      drags++;

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
    final target = findTarget();
    return _DragOutcome(found: target != null, attempts: drags);
  }

  /// The live [ScrollPosition] of [scrollable], or null if there is not one.
  ///
  /// Deliberately total. Candidates are collected before any of them is
  /// dragged, and dragging one can unbuild another — a carousel inside a lazy
  /// list, say — leaving an [Element] still referenced but with nothing behind
  /// it. That has to read as a miss, not a crash.
  ScrollPosition? _tryResolveScrollPosition(Element scrollable) {
    if (!scrollable.mounted || scrollable is! StatefulElement) {
      return null;
    }
    final state = scrollable.state;
    if (state is! ScrollableState) {
      return null;
    }
    try {
      return state.position;
    } catch (_) {
      return null;
    }
  }

  bool _hasScrollableRange(ScrollPosition position) {
    return (position.maxScrollExtent - position.minScrollExtent).abs() >
        _positionEpsilon;
  }

  /// The distance to drag per attempt.
  ///
  /// Half of the run of the viewport that can actually receive pointer events,
  /// so consecutive attempts overlap and nothing passes through unseen. A
  /// widget only counts as visible once its centre can be hit, and a centre
  /// crosses that run exactly once on the way past, so a step wider than the
  /// run could stride over a target without ever offering it for inspection.
  ///
  /// Scaling to the viewport rather than creeping by a fixed amount is what
  /// makes long lists reachable at all: the attempt cap is finite, so a small
  /// step puts a ceiling on how far a list can be traversed.
  double _stepFor(Element scrollable, AxisDirection direction) {
    final renderObject = scrollable.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return _minDelta;
    }

    final size = renderObject.size;
    final axis = axisDirectionToAxis(direction);
    final extent = axis == Axis.vertical ? size.height : size.width;
    if (!extent.isFinite || extent <= 0) {
      return _minDelta;
    }

    return (_exposedExtent(scrollable, size, axis) * 0.5)
        .clamp(_minDelta, double.infinity);
  }

  /// The longest uninterrupted run of the viewport along [axis] that can
  /// receive pointer events.
  ///
  /// An app bar, a bottom bar, or any overlay drawn over the viewport hides
  /// part of it from hit testing while leaving the rest usable. Sampling finds
  /// the usable part; the whole extent is assumed when nothing is reachable,
  /// since a scrollable covered end to end cannot be dragged at any step size.
  double _exposedExtent(Element scrollable, Size size, Axis axis) {
    final extent = axis == Axis.vertical ? size.height : size.width;
    final cross = axis == Axis.vertical ? size.width / 2 : size.height / 2;

    var longestRun = 0;
    var currentRun = 0;
    for (var i = 0; i < _exposureSamples; i++) {
      final along = extent * (i + 0.5) / _exposureSamples;
      final point =
          axis == Axis.vertical ? Offset(cross, along) : Offset(along, cross);

      if (isElementHittableAt(scrollable, point)) {
        currentRun++;
        if (currentRun > longestRun) {
          longestRun = currentRun;
        }
      } else {
        currentRun = 0;
      }
    }

    if (longestRun == 0) {
      return extent;
    }

    return extent * longestRun / _exposureSamples;
  }

  int _calculateMaxScrollAttempts(ScrollPosition position, double delta) {
    final scrollExtent =
        (position.maxScrollExtent - position.minScrollExtent).abs();
    if (!scrollExtent.isFinite) {
      return _fallbackMaxScrollAttempts
          .clamp(1, _defaultMaxScrollAttemptsCap)
          .toInt();
    }

    final oneWayAttempts = (scrollExtent / delta).ceil();

    // Allow one full pass in one direction and another after reverse,
    // with a small buffer for viewport alignment near edges.
    final adaptiveAttempts = oneWayAttempts * 2 + _attemptPadding;
    return adaptiveAttempts.clamp(1, _defaultMaxScrollAttemptsCap).toInt();
  }
}

/// What one pass over a single [Scrollable] achieved.
class _DragOutcome {
  const _DragOutcome({required this.found, required this.attempts});

  final bool found;
  final int attempts;
}
