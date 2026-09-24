import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Waits until Flutter's scheduler has no pending transient callbacks — i.e.
/// no route transition, animation, or other ticker is currently running.
///
/// This is the same condition `flutter_driver`'s `NoTransientCallbacksCondition`
/// uses to decide that an app has settled: it polls
/// [SchedulerBinding.transientCallbackCount] once per frame (via
/// [SchedulerBinding.endOfFrame]) rather than waiting a fixed delay, so it
/// works regardless of how long or short a given transition's animation is.
///
/// Returns `true` once settled, or `false` if [timeout] elapses first.
/// Callers should treat a `false` result as "this app may never settle" (a
/// persistent spinner or looping video keeps `transientCallbackCount` above
/// zero forever) rather than waiting again.
Future<bool> waitForNoTransientCallbacks({required Duration timeout}) async {
  final scheduler = SchedulerBinding.instance;
  bool settled() => scheduler.transientCallbackCount == 0;

  if (settled()) {
    return true;
  }

  final timedOut = Completer<void>();
  final timer = Timer(timeout, timedOut.complete);

  // Raced against timedOut.future because endOfFrame never completes if the
  // engine stops producing frames entirely (e.g. the app is backgrounded)
  // while transient callbacks are still queued -- awaiting it alone would
  // hang past the timeout.
  while (!settled() && !timedOut.isCompleted) {
    await Future.any([scheduler.endOfFrame, timedOut.future]);
  }
  timer.cancel();

  return settled();
}
