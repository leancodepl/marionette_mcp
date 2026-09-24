import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Waits until no [Navigator] in the app is in the middle of a route
/// transition, so a pop can't land on a route that is still animating in.
///
/// Only route transitions are considered: a spinner, looping video or any
/// other animation that isn't a route moving on or off screen doesn't delay
/// this. That is the difference from waiting for
/// [SchedulerBinding.transientCallbackCount] to reach zero, which never
/// happens on a screen with a persistent animation.
///
/// Returns `true` once no route is transitioning, or `false` if [timeout]
/// elapses first.
Future<bool> waitForRouteTransitions({required Duration timeout}) async {
  final scheduler = SchedulerBinding.instance;
  final timedOut = Completer<void>();
  final timer = Timer(timeout, timedOut.complete);

  // Raced against timedOut.future because endOfFrame never completes if the
  // engine stops producing frames (e.g. the app is backgrounded).
  Future<void> nextFrame() =>
      Future.any([scheduler.endOfFrame, timedOut.future]);

  try {
    // A navigation requested just before — e.g. by the tap that pushed the
    // route, when a router applies it on its next rebuild — only reaches the
    // Navigator once the pending frame runs.
    if (scheduler.hasScheduledFrame) {
      await nextFrame();
    }

    while (_isAnyRouteTransitioning()) {
      if (timedOut.isCompleted) {
        return false;
      }
      await nextFrame();
    }

    return true;
  } finally {
    timer.cancel();
  }
}

bool _isAnyRouteTransitioning() {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) {
    return false;
  }

  var transitioning = false;
  void visit(Element element) {
    if (transitioning) {
      return;
    }
    if (element is StatefulElement && element.state is NavigatorState) {
      transitioning = _isTransitioning(element.state as NavigatorState);
      if (transitioning) {
        return;
      }
    }
    element.visitChildren(visit);
  }

  visit(root);

  return transitioning;
}

bool _isTransitioning(NavigatorState navigator) {
  if (navigator.userGestureInProgress) {
    return true;
  }

  // Returning true on the first candidate makes popUntil a read-only peek at
  // the top route — the one a pop would act on — without popping anything.
  Route<dynamic>? top;
  navigator.popUntil((route) {
    top = route;
    return true;
  });

  final route = top;

  return route is TransitionRoute && (route.animation?.isAnimating ?? false);
}
