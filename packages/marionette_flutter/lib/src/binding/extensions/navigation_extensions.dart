import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/settle_waiter.dart';

/// How long [pressBackButton] waits for a running transition to finish
/// before giving up.
const defaultSettleTimeout = Duration(seconds: 5);

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

/// Presses the back button, waiting for any running transition to finish
/// first.
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
/// Waiting via [waitForNoTransientCallbacks] avoids that: once no animation
/// or other ticker is running, the route has already settled into its
/// stable lifecycle state, so the pop — refused or not — can't land
/// mid-transition. A fixed delay can't stand in for this, since it would
/// either fire too early for slow/custom transitions or needlessly slow
/// down fast ones.
///
/// If the app never settles within [settleTimeout] — a persistent
/// animation such as a spinner or looping video — returns an error instead
/// of popping anyway, which would reintroduce the bug.
@visibleForTesting
Future<MarionetteExtensionResult> pressBackButton({
  required Future<bool> Function() handlePopRoute,
  Duration settleTimeout = defaultSettleTimeout,
}) async {
  final settled = await waitForNoTransientCallbacks(timeout: settleTimeout);
  if (!settled) {
    return MarionetteExtensionResult.error(
      0,
      'The app never settled (an animation or other ticker kept running) '
      'within ${settleTimeout.inMilliseconds}ms. The back button press was '
      'not delivered, to avoid popping the route mid-transition.',
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
