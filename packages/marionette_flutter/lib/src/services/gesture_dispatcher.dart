import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 10);

  static const _kDeviceId = 1;

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
      await _dispatchTapAtPosition(matcher.offset);
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
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    // Get the center position of the widget
    final center = renderObject.size.center(Offset.zero);
    final globalPosition = renderObject.localToGlobal(center);

    await _dispatchTapAtPosition(globalPosition);
  }

  Future<void> _dispatchTapAtPosition(Offset globalPosition) async {
    final pointerId = _nextPointerId++;

    // Build the event records
    final records = [
      // Pointer down immediately
      [
        PointerAddedEvent(position: globalPosition, device: _kDeviceId),
        PointerDownEvent(
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
      ],
      // Pointer up after a short delay, then remove the device
      [
        PointerUpEvent(
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
        PointerRemovedEvent(position: globalPosition, device: _kDeviceId),
      ],
    ];

    await _handlePointerEventRecord(records);
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
      await _dispatchLongPressAtPosition(matcher.offset, duration);
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
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    final globalPosition = renderObject.localToGlobal(center);

    await _dispatchLongPressAtPosition(globalPosition, duration);
  }

  Future<void> _dispatchLongPressAtPosition(
    Offset globalPosition,
    Duration duration,
  ) async {
    final pointerId = _nextPointerId++;

    final records = [
      [
        PointerAddedEvent(position: globalPosition, device: _kDeviceId),
        PointerDownEvent(
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
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
            pointer: pointerId, position: globalPosition, device: _kDeviceId),
        PointerRemovedEvent(position: globalPosition, device: _kDeviceId),
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

    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final center = renderObject.size.center(Offset.zero);
    final start = renderObject.localToGlobal(center);

    final end = switch (direction) {
      'left' => start + Offset(-distance, 0),
      'right' => start + Offset(distance, 0),
      'up' => start + Offset(0, -distance),
      'down' => start + Offset(0, distance),
      _ => throw ArgumentError('Invalid direction: $direction. '
          'Must be one of: left, right, up, down'),
    };

    await drag(start, end);
  }

  /// Simulates a drag gesture from [from] to [to].
  Future<void> drag(Offset from, Offset to) async {
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
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(position: from, device: _kDeviceId),
        PointerDownEvent(
            pointer: pointerId, position: from, device: _kDeviceId),
      ],
      ...moveRecords,
      [
        PointerUpEvent(pointer: pointerId, position: to, device: _kDeviceId),
        PointerRemovedEvent(position: to, device: _kDeviceId),
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
