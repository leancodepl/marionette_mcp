import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/extensions/extension_helpers.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/scroll_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Registers gesture-based `marionette.*` extensions: tap, doubleTap,
/// longPress, swipe, pinchZoom, scrollTo.
void registerGestureExtensions({
  required GestureDispatcher gestureDispatcher,
  required WidgetFinder widgetFinder,
  required ScrollSimulator scrollSimulator,
  required MarionetteConfiguration configuration,
}) {
  registerInternalMarionetteExtension(
    name: 'marionette.tap',
    callback: (params) async {
      final matcher = WidgetMatcher.fromJson(params);
      await gestureDispatcher.tap(matcher, widgetFinder, configuration);
      return MarionetteExtensionResult.success({
        'message': 'Tapped element matching: ${matcher.toJson()}',
      });
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.doubleTap',
    callback: (params) async {
      final parsed = parseDurationMs(
        params,
        'delay',
        defaultValue: const Duration(milliseconds: 100),
        requirePositive: true,
      );
      if (parsed.error case final error?) {
        return error;
      }
      final matcher = WidgetMatcher.fromJson(params);
      await gestureDispatcher.doubleTap(
        matcher,
        widgetFinder,
        configuration,
        delay: parsed.duration!,
      );
      return MarionetteExtensionResult.success({
        'message': 'Double tapped element matching: ${matcher.toJson()}',
      });
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.longPress',
    callback: (params) async {
      final parsed = parseDurationMs(
        params,
        'duration',
        defaultValue: const Duration(milliseconds: 600),
      );
      if (parsed.error case final error?) {
        return error;
      }
      final matcher = WidgetMatcher.fromJson(params);
      await gestureDispatcher.longPress(
        matcher,
        widgetFinder,
        configuration,
        duration: parsed.duration!,
      );
      return MarionetteExtensionResult.success({
        'message': 'Long pressed element matching: ${matcher.toJson()}',
      });
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.swipe',
    callback: (params) async {
      if (params.containsKey('startX')) {
        final startXStr = params['startX'];
        final startYStr = params['startY'];
        final endXStr = params['endX'];
        final endYStr = params['endY'];

        if (startXStr == null ||
            startYStr == null ||
            endXStr == null ||
            endYStr == null) {
          return MarionetteExtensionResult.invalidParams(
            'Coordinate-based swipe requires all of: '
            'startX, startY, endX, endY',
          );
        }

        final startX = double.tryParse(startXStr);
        final startY = double.tryParse(startYStr);
        final endX = double.tryParse(endXStr);
        final endY = double.tryParse(endYStr);

        if (startX == null || startY == null || endX == null || endY == null) {
          return MarionetteExtensionResult.invalidParams(
            'Invalid coordinate values. '
            'startX, startY, endX, endY must be valid numbers.',
          );
        }

        await gestureDispatcher.drag(
          Offset(startX, startY),
          Offset(endX, endY),
        );

        return MarionetteExtensionResult.success({
          'message': 'Swiped from ($startX, $startY) to ($endX, $endY)',
        });
      }

      final matcher = WidgetMatcher.fromJson(params);
      final direction = params['direction'];
      if (direction == null) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: direction '
          '(must be one of: left, right, up, down)',
        );
      }

      final distanceStr = params['distance'];
      final double distance;
      if (distanceStr != null) {
        final parsed = double.tryParse(distanceStr);
        if (parsed == null) {
          return MarionetteExtensionResult.invalidParams(
            'Invalid distance value: "$distanceStr". '
            'Must be a valid number.',
          );
        }
        distance = parsed;
      } else {
        distance = 200.0;
      }

      await gestureDispatcher.swipe(
        matcher,
        widgetFinder,
        configuration,
        direction: direction,
        distance: distance,
      );

      return MarionetteExtensionResult.success({
        'message': 'Swiped $direction on element matching: ${matcher.toJson()}',
      });
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.pinchZoom',
    callback: (params) async {
      // `scale` is required, so handle it inline rather than via the
      // optional-with-default helper.
      final rawScale = params['scale'];
      if (rawScale == null) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: scale',
        );
      }
      final scale = double.tryParse(rawScale);
      if (scale == null || scale <= 0) {
        return MarionetteExtensionResult.invalidParams(
          'Parameter "scale" must be a positive number, got "$rawScale"',
        );
      }

      final distanceParse = parsePositiveDouble(
        params,
        'startDistance',
        defaultValue: 200.0,
      );
      if (distanceParse.error case final error?) {
        return error;
      }

      final WidgetMatcher matcher;
      try {
        matcher = WidgetMatcher.fromJson(params);
      } on ArgumentError {
        return MarionetteExtensionResult.invalidParams(
          'Missing required selector: provide "key", "text", "type", '
          'or "x" & "y" coordinates.',
        );
      }

      await gestureDispatcher.pinchZoom(
        matcher,
        widgetFinder,
        configuration,
        scale: scale,
        startDistance: distanceParse.value!,
      );

      return MarionetteExtensionResult.success({
        'message': 'Pinch zoomed (scale: $scale) on element matching: '
            '${matcher.toJson()}',
      });
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.scrollTo',
    callback: (params) async {
      final matcher = WidgetMatcher.fromJson(params);
      await scrollSimulator.scrollUntilVisible(matcher, configuration);
      return MarionetteExtensionResult.success({
        'message': 'Scrolled to element matching: ${matcher.toJson()}',
      });
    },
  );
}
