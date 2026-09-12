import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

void main() {
  // Replaces the default bindings so the implicit view can be hidden inside a
  // test body, which is the only state in which no view is resolvable at all.
  final binding = _NoImplicitViewWidgetsBinding();

  testWidgets(
    'a gesture refuses to dispatch when no view can be resolved',
    timeout: const Timeout(Duration(seconds: 30)),
    (WidgetTester tester) async {
      final events = <PointerEvent>[];
      void record(PointerEvent event) => events.add(event);

      GestureBinding.instance.pointerRouter.addGlobalRoute(record);
      addTearDown(
        () => GestureBinding.instance.pointerRouter.removeGlobalRoute(record),
      );

      binding.hideAllViews();
      try {
        expect(WidgetsBinding.instance.renderViews, isEmpty);
        expect(
          WidgetsBinding.instance.platformDispatcher.implicitView,
          isNull,
        );

        // Called without runAsync on purpose: the refusal happens before the
        // dispatcher awaits anything, so the returned future is already failed
        // — and a dispatcher that does not refuse hangs on its own delays,
        // which the test timeout above turns into a failure either way.
        await expectLater(
          GestureDispatcher().tap(
            const CoordinatesMatcher(100, 100),
            WidgetFinder(),
            const MarionetteConfiguration(),
          ),
          throwsA(
            isA<StateError>().having(
              (StateError error) => error.message,
              'message',
              contains('no view is being rendered'),
            ),
          ),
        );
      } finally {
        binding.showAllViews();
      }

      expect(
        events,
        isEmpty,
        reason: 'Nothing may be dispatched when there is no view to dispatch '
            'it to — an event without a resolvable view silently targets the '
            'implicit view and hits nothing',
      );
    },
  );
}

/// A [TestPlatformDispatcher] whose `implicitView` can be hidden.
class _NoImplicitViewPlatformDispatcher extends TestPlatformDispatcher {
  _NoImplicitViewPlatformDispatcher({required super.platformDispatcher})
      : _superPlatformDispatcher = platformDispatcher;

  final PlatformDispatcher _superPlatformDispatcher;

  bool implicitViewHidden = false;

  @override
  TestFlutterView? get implicitView => implicitViewHidden
      ? null
      : _superPlatformDispatcher.implicitView as TestFlutterView?;
}

/// Test bindings that can report having no view at all, modelled on Flutter's
/// own `packages/flutter/test/widgets/multi_view_testing.dart`.
///
/// The test harness always keeps one [RenderView] around for the implicit
/// view, so hiding the implicit view alone is not enough to reproduce an app
/// that has no view to dispatch to — [renderViews] is hidden along with it.
class _NoImplicitViewWidgetsBinding extends AutomatedTestWidgetsFlutterBinding {
  late final _NoImplicitViewPlatformDispatcher _platformDispatcher =
      _NoImplicitViewPlatformDispatcher(
    platformDispatcher: super.platformDispatcher,
  );

  bool _viewsHidden = false;

  @override
  _NoImplicitViewPlatformDispatcher get platformDispatcher =>
      _platformDispatcher;

  @override
  Iterable<RenderView> get renderViews =>
      _viewsHidden ? const <RenderView>[] : super.renderViews;

  void hideAllViews() {
    _viewsHidden = true;
    platformDispatcher.implicitViewHidden = true;
  }

  void showAllViews() {
    _viewsHidden = false;
    platformDispatcher.implicitViewHidden = false;
  }
}
