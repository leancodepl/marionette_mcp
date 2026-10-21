import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/route_transition_waiter.dart';

/// How long [pressBackButton] waits for a route transition to finish before
/// giving up.
const defaultTransitionTimeout = Duration(seconds: 5);

/// Registers navigation-related `marionette.*` extensions: pressBackButton.
///
/// [handlePopRoute] performs the actual pop. In production this is
/// [MarionetteBinding.handlePopRoute] (inherited from [WidgetsBinding]) — the
/// same method a genuine Android back press reaches, so there is no separate
/// "real back press" path to special-case; only timing differs.
void registerNavigationExtensions({
  required Future<bool> Function() handlePopRoute,
}) {
  registerInternalMarionetteExtension(
    name: 'marionette.pressBackButton',
    callback: (params) => pressBackButton(handlePopRoute: handlePopRoute),
  );
}

/// Presses the back button, first waiting for any route transition in flight
/// to finish.
///
/// Calling [handlePopRoute] mid-transition is what
/// https://github.com/leancodepl/marionette_mcp/issues/113 hit: a
/// page-based `Navigator` (the shape `go_router` produces) that refuses the
/// pop — because the route has local history or declares `onExit` — trips
/// `navigator.dart`'s internal route-lifecycle assertion when the popped
/// route is still animating in. One failed call poisons the session, since
/// the assertion throws before `Navigator`'s internal lock resets, so every
/// later navigation fails too — there's no recovering by retrying.
///
/// [waitForRouteTransitions] avoids that without being held up by
/// animations unrelated to navigation, such as a loading spinner on the
/// current screen.
///
/// If a transition is still running after [transitionTimeout], returns an
/// error instead of popping anyway, which would reintroduce the bug.
@visibleForTesting
Future<MarionetteExtensionResult> pressBackButton({
  required Future<bool> Function() handlePopRoute,
  Duration transitionTimeout = defaultTransitionTimeout,
}) async {
  final settled = await waitForRouteTransitions(timeout: transitionTimeout);
  if (!settled) {
    return MarionetteExtensionResult.error(
      0,
      'A route transition was still running after '
      '${transitionTimeout.inMilliseconds}ms. The back button press was not '
      'delivered, to avoid popping the route mid-transition.',
    );
  }

  final didPop = await handlePopRoute();

  return MarionetteExtensionResult.success({
    'didPop': didPop,
    'message': didPop
        ? 'Back button pressed, route was popped'
        : 'Back button pressed, no route to pop (app may exit)',
  });
}
