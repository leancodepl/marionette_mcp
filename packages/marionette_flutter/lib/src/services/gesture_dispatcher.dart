import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/hit_test_utils.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 10);

  static const _kDeviceId = 1;
  static const _kSecondDeviceId = 2;
  static const _kMouseDeviceId = 3;

  int _nextPointerId = 1;

  /// Simulates a tap on an element that matches the given [matcher].
  ///
  /// If [matcher] is a [CoordinatesMatcher], taps directly at the specified
  /// coordinates without searching the widget tree (fast path).
  Future<void> tap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration,
  ) async {
    // Fast path for coordinate-based tapping
    if (matcher is CoordinatesMatcher) {
      await _dispatchTapAtPosition(matcher.offset, viewId: _defaultViewId());
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchTapAtElement(element);
    }
  }

  Future<void> _dispatchTapAtElement(Element element) async {
    await _dispatchTapAtPosition(
      _globalCenterOf(element),
      viewId: _viewIdOfElement(element),
    );
  }

  /// Returns the id of the view [element] is mounted in.
  ///
  /// Pointer events carry the view they are meant for; without it they are
  /// hit-tested against the implicit view, which renders nothing in an app
  /// driven by the desktop windowing API.
  int _viewIdOfElement(Element element) {
    final viewId = viewIdOf(element);
    if (viewId == null) {
      throw StateError(
        'Cannot dispatch a gesture: the element is not mounted in a View and '
        'there is no implicit view to fall back to',
      );
    }
    return viewId;
  }

  /// Returns the id of the view coordinate-based gestures are dispatched to.
  int _defaultViewId() {
    final viewId = defaultViewId();
    if (viewId == null) {
      throw StateError(
        'Cannot dispatch a gesture: no view is being rendered and there is no '
        'implicit view to fall back to',
      );
    }
    return viewId;
  }

  /// Returns the global position of the center of [element]'s [RenderBox].
  ///
  /// Throws if the element has no [RenderBox] or has not been laid out yet.
  Offset _globalCenterOf(Element element) {
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    return renderObject.localToGlobal(center);
  }

  Future<void> _dispatchTapAtPosition(
    Offset globalPosition, {
    required int viewId,
  }) async {
    final pointerId = _nextPointerId++;

    // Build the event records
    final records = [
      // Pointer down immediately
      [
        PointerAddedEvent(
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerDownEvent(
          pointer: pointerId,
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
      ],
      // Pointer up after a short delay, then remove the device
      [
        PointerUpEvent(
          pointer: pointerId,
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerRemovedEvent(
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a secondary (right mouse button) tap on an element matching
  /// [matcher].
  ///
  /// Dispatches a mouse pointer with [kSecondaryButton] pressed, which is what
  /// Flutter recognises as `onSecondaryTap` (e.g. context menus). Desktop only —
  /// touch devices do not support non-primary buttons.
  Future<void> secondaryTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration,
  ) =>
      _mouseTap(matcher, widgetFinder, configuration,
          buttons: kSecondaryButton);

  Future<void> _mouseTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required int buttons,
  }) async {
    if (matcher is CoordinatesMatcher) {
      await _dispatchMouseTapAtPosition(
        matcher.offset,
        buttons,
        viewId: _defaultViewId(),
      );
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }
    await _dispatchMouseTapAtPosition(
      _globalCenterOf(element),
      buttons,
      viewId: _viewIdOfElement(element),
    );
  }

  Future<void> _dispatchMouseTapAtPosition(
    Offset globalPosition,
    int buttons, {
    required int viewId,
  }) async {
    final pointerId = _nextPointerId++;

    final records = [
      // Mouse moves in and presses the requested button.
      [
        PointerAddedEvent(
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          device: _kMouseDeviceId,
          viewId: viewId,
        ),
        PointerDownEvent(
          pointer: pointerId,
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          buttons: buttons,
          device: _kMouseDeviceId,
          viewId: viewId,
        ),
      ],
      // Button released (buttons: 0), then the device is removed.
      [
        PointerUpEvent(
          pointer: pointerId,
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          buttons: 0,
          device: _kMouseDeviceId,
          viewId: viewId,
        ),
        PointerRemovedEvent(
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          device: _kMouseDeviceId,
          viewId: viewId,
        ),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a double tap on an element that matches the given [matcher].
  ///
  /// Two taps are dispatched with [delay] between them.
  /// Defaults to 100ms, which is within Flutter's double-tap recognition
  /// window (kDoubleTapMinTime 40ms — kDoubleTapTimeout 300ms).
  Future<void> doubleTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    if (delay.isNegative || delay == Duration.zero) {
      throw ArgumentError('delay must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchDoubleTapAtPosition(
        matcher.offset,
        delay,
        viewId: _defaultViewId(),
      );
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchDoubleTapAtElement(element, delay);
    }
  }

  Future<void> _dispatchDoubleTapAtElement(
    Element element,
    Duration delay,
  ) async {
    await _dispatchDoubleTapAtPosition(
      _globalCenterOf(element),
      delay,
      viewId: _viewIdOfElement(element),
    );
  }

  Future<void> _dispatchDoubleTapAtPosition(
    Offset globalPosition,
    Duration delay, {
    required int viewId,
  }) async {
    // First tap
    await _dispatchTapAtPosition(globalPosition, viewId: viewId);

    // Wait between taps for double-tap recognition
    await Future<void>.delayed(delay);

    // Second tap
    await _dispatchTapAtPosition(globalPosition, viewId: viewId);
  }

  /// Simulates a long press on an element that matches the given [matcher].
  ///
  /// The pointer is held down for [duration] before being released.
  /// Defaults to 600ms (kLongPressTimeout + kPressTimeout), matching
  /// Flutter's [WidgetTester.longPress] behavior.
  Future<void> longPress(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    Duration duration = const Duration(milliseconds: 600),
  }) async {
    if (duration.isNegative || duration == Duration.zero) {
      throw ArgumentError('duration must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchLongPressAtPosition(
        matcher.offset,
        duration,
        viewId: _defaultViewId(),
      );
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchLongPressAtElement(element, duration);
    }
  }

  Future<void> _dispatchLongPressAtElement(
    Element element,
    Duration duration,
  ) async {
    await _dispatchLongPressAtPosition(
      _globalCenterOf(element),
      duration,
      viewId: _viewIdOfElement(element),
    );
  }

  Future<void> _dispatchLongPressAtPosition(
    Offset globalPosition,
    Duration duration, {
    required int viewId,
  }) async {
    final pointerId = _nextPointerId++;

    final records = [
      [
        PointerAddedEvent(
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerDownEvent(
          pointer: pointerId,
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
      ],
    ];

    // Dispatch pointer down
    await _handlePointerEventRecord(records);

    // Hold for the specified duration to trigger long press recognition
    await Future<void>.delayed(duration);

    // Release
    await _handlePointerEventRecord([
      [
        PointerUpEvent(
          pointer: pointerId,
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerRemovedEvent(
          position: globalPosition,
          device: _kDeviceId,
          viewId: viewId,
        ),
      ],
    ]);
  }

  /// Simulates a swipe gesture on an element matching [matcher] in the given
  /// [direction] for [distance] pixels.
  ///
  /// The swipe starts from the center of the matched element and moves in the
  /// specified direction.
  Future<void> swipe(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required String direction,
    double distance = 200.0,
  }) async {
    final element = widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    final start = _globalCenterOf(element);

    final end = switch (direction) {
      'left' => start + Offset(-distance, 0),
      'right' => start + Offset(distance, 0),
      'up' => start + Offset(0, -distance),
      'down' => start + Offset(0, distance),
      _ => throw ArgumentError('Invalid direction: $direction. '
          'Must be one of: left, right, up, down'),
    };

    await drag(start, end, viewId: _viewIdOfElement(element));
  }

  /// Simulates a pinch zoom gesture centered on an element matching [matcher].
  ///
  /// [scale] controls the zoom:
  /// - scale > 1.0: zoom in (fingers move apart)
  /// - scale < 1.0: zoom out (fingers move together)
  ///
  /// [startDistance] is the initial distance between the two fingers in pixels.
  Future<void> pinchZoom(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    required double scale,
    double startDistance = 200.0,
  }) async {
    if (scale <= 0) {
      throw ArgumentError('scale must be positive');
    }
    if (startDistance <= 0) {
      throw ArgumentError('startDistance must be positive');
    }

    if (matcher is CoordinatesMatcher) {
      await _dispatchPinchZoomAtPosition(
        matcher.offset,
        scale: scale,
        startDistance: startDistance,
        viewId: _defaultViewId(),
      );
      return;
    }

    final element = widgetFinder.findHittableElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    final globalCenter = _globalCenterOf(element);

    await _dispatchPinchZoomAtPosition(
      globalCenter,
      scale: scale,
      startDistance: startDistance,
      viewId: _viewIdOfElement(element),
    );
  }

  Future<void> _dispatchPinchZoomAtPosition(
    Offset center, {
    required double scale,
    required double startDistance,
    required int viewId,
  }) async {
    final pointer1Id = _nextPointerId++;
    final pointer2Id = _nextPointerId++;
    final endDistance = startDistance * scale;

    const stepCount = 10;

    // Finger positions: horizontally offset from center
    Offset finger1(double distance) => center - Offset(distance / 2, 0);
    Offset finger2(double distance) => center + Offset(distance / 2, 0);

    final start1 = finger1(startDistance);
    final start2 = finger2(startDistance);

    // Phase 1: Both fingers down
    final records = <List<PointerEvent>>[
      [
        PointerAddedEvent(
          position: start1,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerDownEvent(
          pointer: pointer1Id,
          position: start1,
          device: _kDeviceId,
          viewId: viewId,
        ),
      ],
      [
        PointerAddedEvent(
          position: start2,
          device: _kSecondDeviceId,
          viewId: viewId,
        ),
        PointerDownEvent(
          pointer: pointer2Id,
          position: start2,
          device: _kSecondDeviceId,
          viewId: viewId,
        ),
      ],
    ];

    // Phase 2: Move fingers apart (zoom in) or together (zoom out)
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final currentDistance = startDistance + (endDistance - startDistance) * t;
      final pos1 = finger1(currentDistance);
      final pos2 = finger2(currentDistance);

      records.add([
        PointerMoveEvent(
          pointer: pointer1Id,
          position: pos1,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerMoveEvent(
          pointer: pointer2Id,
          position: pos2,
          device: _kSecondDeviceId,
          viewId: viewId,
        ),
      ]);
    }

    // Phase 3: Both fingers up
    final end1 = finger1(endDistance);
    final end2 = finger2(endDistance);

    records.addAll([
      [
        PointerUpEvent(
          pointer: pointer1Id,
          position: end1,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerUpEvent(
          pointer: pointer2Id,
          position: end2,
          device: _kSecondDeviceId,
          viewId: viewId,
        ),
      ],
      [
        PointerRemovedEvent(
          position: end1,
          device: _kDeviceId,
          viewId: viewId,
        ),
        PointerRemovedEvent(
          position: end2,
          device: _kSecondDeviceId,
          viewId: viewId,
        ),
      ],
    ]);

    await _handlePointerEventRecord(records);
  }

  /// Simulates a drag gesture from [from] to [to].
  ///
  /// [viewId] is the view the drag is dispatched to; it defaults to the first
  /// rendered view. Callers that start from an element should pass that
  /// element's view instead.
  Future<void> drag(Offset from, Offset to, {int? viewId}) async {
    final resolvedViewId = viewId ?? _defaultViewId();
    final pointerId = _nextPointerId++;

    final delta = to - from;
    final distance = delta.distance;
    final stepCount =
        (distance / kMaxDelta).ceil().clamp(1, double.infinity).toInt();

    final moveRecords = <List<PointerEvent>>[];
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final position = Offset.lerp(from, to, t)!;
      final previousPosition =
          i == 1 ? from : Offset.lerp(from, to, (i - 1) / stepCount)!;
      final stepDelta = position - previousPosition;

      moveRecords.add([
        PointerMoveEvent(
          pointer: pointerId,
          position: position,
          delta: stepDelta,
          device: _kDeviceId,
          viewId: resolvedViewId,
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(
          position: from,
          device: _kDeviceId,
          viewId: resolvedViewId,
        ),
        PointerDownEvent(
          pointer: pointerId,
          position: from,
          device: _kDeviceId,
          viewId: resolvedViewId,
        ),
      ],
      ...moveRecords,
      [
        PointerUpEvent(
          pointer: pointerId,
          position: to,
          device: _kDeviceId,
          viewId: resolvedViewId,
        ),
        PointerRemovedEvent(
          position: to,
          device: _kDeviceId,
          viewId: resolvedViewId,
        ),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Handles a list of pointer event records by dispatching them with proper timing.
  ///
  /// Similar to Flutter's test framework handlePointerEventRecord, but simplified
  /// for live app execution.
  Future<void> _handlePointerEventRecord(
    List<List<PointerEvent>> records,
  ) async {
    for (final record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(kDelay);
    }
  }
}
