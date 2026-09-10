import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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

  final view = element.findAncestorWidgetOfExactType<View>();
  final viewId = view?.view.viewId ??
      WidgetsBinding.instance.platformDispatcher.implicitView?.viewId;
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

/// Checks whether [element] or one of its visible descendants can receive
/// pointer events, within a bounded traversal.
///
/// A composite widget can delegate hit testing to a private render-object
/// child without adding its own render object to the hit-test path. Adapters
/// describe the public composite element, so discovery and action lookup need
/// to accept the descendant that implements its pointer behavior.
bool isElementOrDescendantHittable(
  Element element, {
  int maxVisitedElements = 512,
}) {
  if (maxVisitedElements <= 0) {
    return false;
  }
  var remaining = maxVisitedElements;

  bool visit(Element candidate) {
    if (remaining <= 0) {
      return false;
    }
    remaining--;

    final widget = candidate.widget;
    if ((widget is Offstage && widget.offstage) ||
        (widget is Visibility && !widget.visible)) {
      return false;
    }
    if (isElementHittable(candidate)) {
      return true;
    }

    var result = false;
    candidate.visitChildren((child) {
      if (!result) {
        result = visit(child);
      }
    });
    return result;
  }

  return visit(element);
}
