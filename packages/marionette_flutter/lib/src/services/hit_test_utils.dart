import 'dart:ui' show FlutterView;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Returns the view the [element] is mounted in.
///
/// The single place the element-to-view question is answered, so discovery,
/// dispatch and the visibility check cannot drift apart. Falls back to the
/// implicit view for an element that is not below a [View] of its own, and
/// returns null when there is no view to resolve at all.
FlutterView? viewOf(Element element) {
  final view = element.findAncestorWidgetOfExactType<View>();
  return view?.view ?? WidgetsBinding.instance.platformDispatcher.implicitView;
}

/// Returns the id of the view the [element] is mounted in.
int? viewIdOf(Element element) => viewOf(element)?.viewId;

/// Returns the id of the view to use when there is no element to ask.
///
/// Prefers the first rendered view: in an ordinary app that is the implicit
/// view, and in an app driven by the desktop windowing API the implicit view
/// exists but is never rendered, so the first rendered view is the window the
/// user sees. Returns null when nothing is rendered and there is no implicit
/// view either.
int? defaultViewId() {
  // Not `firstOrNull`: that lives in package:collection, which this package
  // does not depend on.
  final renderViews = WidgetsBinding.instance.renderViews;
  if (renderViews.isNotEmpty) {
    return renderViews.first.flutterView.viewId;
  }
  return WidgetsBinding.instance.platformDispatcher.implicitView?.viewId;
}

/// Checks if the [element] can receive pointer events.
///
/// Performs a hit test at the center of the element and checks whether its
/// render object appears in the hit test path. Elements behind modal
/// barriers, [AbsorbPointer], [IgnorePointer], or offscreen will return
/// false.
bool isElementHittable(Element element) {
  final renderObject = element.renderObject;
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return false;
  }

  return isElementHittableAt(element, renderObject.size.center(Offset.zero));
}

/// Checks if the [element] can receive pointer events at [localPoint].
///
/// [localPoint] is in the element's own coordinate space. Use this to probe
/// which parts of a large element are actually exposed — a viewport may be
/// covered by an app bar or a bottom bar over part of its extent while
/// remaining reachable elsewhere.
bool isElementHittableAt(Element element, Offset localPoint) {
  final renderObject = element.renderObject;
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return false;
  }

  if (!renderObject.attached) {
    return false;
  }

  final viewId = viewIdOf(element);
  if (viewId == null) {
    return false;
  }

  try {
    final absoluteOffset = renderObject.localToGlobal(localPoint);

    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, absoluteOffset, viewId);

    for (final entry in result.path) {
      if (entry.target == renderObject) {
        return true;
      }
    }

    return false;
  } catch (_) {
    return false;
  }
}
