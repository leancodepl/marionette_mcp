import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// A [FlutterView] with its own [viewId] that never reaches the engine.
///
/// Mounting content under `View(view: FakeView(tester.view), child: …)` with
/// `pumpWidget(wrapWithView: false, …)` reproduces the shape of an app that
/// renders through the desktop windowing API: the implicit view exists but has
/// no `RenderView`, and everything the user sees lives in another view.
///
/// Modelled on Flutter's own `packages/flutter/test/widgets/multi_view_testing.dart`.
class FakeView extends TestFlutterView {
  FakeView(FlutterView view, {this.viewId = 100})
      : super(
          view: view,
          platformDispatcher: view.platformDispatcher as TestPlatformDispatcher,
          display: view.display as TestDisplay,
        );

  @override
  final int viewId;

  @override
  void render(Scene scene, {Size? size}) {
    // Do not render the scene in the engine: it only observes the one view it
    // was given, and expects no more than one `Scene` per frame.
  }

  @override
  void updateSemantics(SemanticsUpdate update) {
    // Do not send the update to the engine, for the same reason as [render].
  }
}
