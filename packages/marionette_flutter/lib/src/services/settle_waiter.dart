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

  var timedOut = false;
  final timer = Timer(timeout, () => timedOut = true);

  while (!settled() && !timedOut) {
    await scheduler.endOfFrame;
  }
  timer.cancel();

  return settled();
}
