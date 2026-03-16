import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 10);

  int _nextPointerId = 1;

  /// Synthetic device IDs start high to avoid colliding with real hardware
  /// devices (real mouse is device 0). MouseTracker tracks by device ID,
  /// so each synthetic tap sequence needs its own unique device to prevent
  /// the assertion: (event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent).
  int _nextDeviceId = 100000;

  /// Gets the viewId of the first (primary) Flutter view.
  /// On macOS/Linux/Windows desktop, this may not be 0 — using the wrong
  /// viewId causes hitTestInView to miss all render objects, making taps
  /// silently fail.
  int get _viewId =>
      WidgetsBinding.instance.platformDispatcher.views.first.viewId;

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
    final deviceId = _nextDeviceId++;
    final viewId = _viewId;

    // Build the event records.
    // pointer ID must match across Added→Down→Up→Removed so Flutter's
    // gesture arena can track the full sequence and fire onTap callbacks.
    // device ID must be unique per sequence and different from real hardware
    // (real mouse = device 0) to avoid MouseTracker assertion failures.
    // viewId must match the actual Flutter view so hitTestInView finds the
    // correct render tree (on desktop, viewId is often non-zero).
    final records = [
      // Pointer added + down
      [
        PointerAddedEvent(
          pointer: pointerId,
          device: deviceId,
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
        ),
        PointerDownEvent(
          pointer: pointerId,
          device: deviceId,
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
        ),
      ],
      // Pointer up + removed after a short delay
      [
        PointerUpEvent(
          pointer: pointerId,
          device: deviceId,
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
        ),
        PointerRemovedEvent(
          pointer: pointerId,
          device: deviceId,
          position: globalPosition,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
        ),
      ],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a drag gesture from [from] to [to].
  Future<void> drag(Offset from, Offset to) async {
    final pointerId = _nextPointerId++;
    final deviceId = _nextDeviceId++;
    final viewId = _viewId;

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
          device: deviceId,
          position: position,
          delta: stepDelta,
          viewId: viewId,
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(
          pointer: pointerId,
          device: deviceId,
          position: from,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
        ),
        PointerDownEvent(
          pointer: pointerId,
          device: deviceId,
          position: from,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
        ),
      ],
      ...moveRecords,
      [
        PointerUpEvent(
          pointer: pointerId,
          device: deviceId,
          position: to,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
        ),
        PointerRemovedEvent(
          pointer: pointerId,
          device: deviceId,
          position: to,
          kind: PointerDeviceKind.mouse,
          viewId: viewId,
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
