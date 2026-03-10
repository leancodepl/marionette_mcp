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
    final center = renderObject.size.center(Offset.zero);
    final absoluteOffset = renderObject.localToGlobal(center);

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
