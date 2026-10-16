import 'dart:math' show min;

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/native_service/tools/selector_args.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

const _defaultSwipeDistance = 400;
const _maxScrollAttempts = 10;

/// Finger-swipe direction for [native_scroll] (screen coordinates).
enum SwipeDirection {
  up('up'),
  down('down'),
  left('left'),
  right('right');

  const SwipeDirection(this.wireName);

  /// MCP tool argument value (e.g. `"up"`).
  final String wireName;

  static String get commaSeparatedWireNames =>
      values.map((direction) => direction.wireName).join(', ');

  static String get quotedWireNames {
    final quoted =
        values.map((direction) => '"${direction.wireName}"').toList();
    if (quoted.length <= 1) return quoted.join();
    return '${quoted.sublist(0, quoted.length - 1).join(', ')}, or ${quoted.last}';
  }

  static SwipeDirection? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.toLowerCase().trim();
    for (final direction in values) {
      if (direction.wireName == normalized) return direction;
    }
    return null;
  }

  ({int startX, int startY, int endX, int endY}) swipeEndpoints({
    required int centerX,
    required int centerY,
    required int half,
  }) {
    return switch (this) {
      SwipeDirection.up => (
          startX: centerX,
          startY: centerY + half,
          endX: centerX,
          endY: centerY - half,
        ),
      SwipeDirection.down => (
          startX: centerX,
          startY: centerY - half,
          endX: centerX,
          endY: centerY + half,
        ),
      SwipeDirection.left => (
          startX: centerX + half,
          startY: centerY,
          endX: centerX - half,
          endY: centerY,
        ),
      SwipeDirection.right => (
          startX: centerX - half,
          startY: centerY,
          endX: centerX + half,
          endY: centerY,
        ),
    };
  }
}

/// Registers native tap and scroll tools.
void registerNativeGestureTools(
  McpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_tap',
      description:
          'Taps a native / system control, chosen by a selector (text, '
          'textContains, id, type, optional index — values from '
          'native_get_elements) or by x+y coordinates in screenshot pixels '
          '(the pixel grid of native_take_screenshot and of the bounds in '
          'native_get_elements). Use either a selector or x+y, not both. '
          '$nativeSelectorRules '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Tap'),
      inputSchema: ToolInputSchema(
        properties: {
          ...nativeSelectorProperties(),
          'x': JsonSchema.number(
            description: 'X coordinate in screenshot pixels. Must be paired '
                'with y. Do not use Flutter logical coordinates.',
          ),
          'y': JsonSchema.number(
            description: 'Y coordinate in screenshot pixels. Must be paired '
                'with x. Do not use Flutter logical coordinates.',
          ),
        },
      ),
      callback: (args, extra) => handleNativeTap(context, args),
    )
    ..registerTool(
      'native_scroll',
      description:
          'Performs a native swipe gesture. direction is the finger-swipe '
          'direction: ${SwipeDirection.commaSeparatedWireNames}. Swipes from '
          'screen center by default; optional startX/startY set the finger '
          'start (screenshot pixels). Optional distance defaults to '
          '$_defaultSwipeDistance. '
          'If a target selector (text, textContains, id, type) is given, '
          'swipes repeatedly until a matching element is visible (max '
          '$_maxScrollAttempts swipes) or fails. '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Scroll'),
      inputSchema: ToolInputSchema(
        properties: {
          'direction': JsonSchema.string(
            description:
                'Finger-swipe direction: ${SwipeDirection.quotedWireNames}.',
          ),
          ...nativeSelectorProperties(withIndex: false),
          'distance': JsonSchema.number(
            description: 'Swipe distance in screenshot pixels '
                '(default: $_defaultSwipeDistance).',
          ),
          'startX': JsonSchema.number(
            description: 'Optional finger start X in screenshot pixels. '
                'Requires startY. Default: screen center.',
          ),
          'startY': JsonSchema.number(
            description: 'Optional finger start Y in screenshot pixels. '
                'Requires startX.',
          ),
        },
        required: ['direction'],
      ),
      callback: (args, extra) => handleNativeScroll(context, args),
    );
}

/// Handles `native_tap`.
Future<CallToolResult> handleNativeTap(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final selector = nativeSelectorFromArgs(args);
  final coordinates = argPairPresence(args, 'x', 'y');
  final hasCoords = coordinates != ArgPairPresence.none;
  final hasSelector = !selector.isEmpty;

  if (hasSelector == hasCoords) {
    return invalidArguments(
      'native_tap requires either a selector (text, textContains, id, type) '
      'or both x and y — not both, not neither.',
    );
  }
  if (coordinates == ArgPairPresence.partial) {
    return invalidArguments(
      'native_tap coordinate mode requires both x and y.',
    );
  }
  if (hasCoords && selector.index != null) {
    return invalidArguments('native_tap index requires a selector.');
  }

  logger.info('Native tapping with args: $args');
  return runTool(logger, 'native tap', () async {
    final connector = context.requireConnector();

    if (hasCoords) {
      final x = intArg(args, 'x')!;
      final y = intArg(args, 'y')!;
      await connector.tapAt(x, y);
      return CallToolResult(
        content: [TextContent(text: 'Successfully tapped at ($x, $y)')],
      );
    }

    final match = selectElement(await connector.getNativeElements(), selector);
    await connector.tapElement(match);
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully tapped native element ${selector.describe()}',
        ),
      ],
    );
  });
}

/// Handles `native_scroll`.
Future<CallToolResult> handleNativeScroll(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final direction = SwipeDirection.tryParse(args['direction'] as String?);
  final target = nativeSelectorFromArgs(args);
  final distance = intArg(args, 'distance');
  final startX = intArg(args, 'startX');
  final startY = intArg(args, 'startY');

  if (direction == null) {
    return invalidArguments(
      'native_scroll requires direction to be '
      '${SwipeDirection.quotedWireNames}.',
    );
  }
  if (distance != null && distance <= 0) {
    return invalidArguments(
      'Parameter "distance" must be a positive integer.',
    );
  }
  if (argPairPresence(args, 'startX', 'startY') == ArgPairPresence.partial) {
    return invalidArguments(
      'native_scroll requires both startX and startY when either is '
      'provided.',
    );
  }

  logger.info(
    'Native scrolling direction=${direction.wireName} '
    'target=${target.describe()} distance=$distance start=($startX,$startY)',
  );
  return runTool(logger, 'native scroll', () async {
    final connector = context.requireConnector();
    final delta = distance ?? _defaultSwipeDistance;

    if (target.isEmpty) {
      await _swipeInDirection(
        connector,
        direction,
        delta,
        startX: startX,
        startY: startY,
      );
      return CallToolResult(
        content: [
          TextContent(
            text: 'Successfully swiped ${direction.wireName} '
                '(distance=$delta)',
          ),
        ],
      );
    }

    for (var attempt = 0; attempt < _maxScrollAttempts; attempt++) {
      final elements = await connector.getNativeElements();
      if (elements.any(target.matches)) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'Found native element ${target.describe()} '
                  'after $attempt swipe(s)',
            ),
          ],
        );
      }
      await _swipeInDirection(
        connector,
        direction,
        delta,
        startX: startX,
        startY: startY,
      );
    }

    throw NativeElementNotFoundException(
      '${target.describe()} after $_maxScrollAttempts swipe(s) in '
      'direction=${direction.wireName}',
    );
  });
}

Future<void> _swipeInDirection(
  NativeConnector connector,
  SwipeDirection direction,
  int distance, {
  int? startX,
  int? startY,
}) async {
  final screen = await connector.getScreen();
  final maxX = screen.width;
  final maxY = screen.height;

  final ({int startX, int startY, int endX, int endY}) endpoints;
  if (startX != null && startY != null) {
    endpoints = swipeFromStart(
      direction: direction,
      startX: startX,
      startY: startY,
      distance: distance,
      maxX: maxX,
      maxY: maxY,
    );
  } else {
    final centerX = maxX ~/ 2;
    final centerY = maxY ~/ 2;
    final half = cappedSwipeHalf(
      direction: direction,
      half: distance ~/ 2,
      centerX: centerX,
      centerY: centerY,
      maxX: maxX,
      maxY: maxY,
    );

    endpoints = direction.swipeEndpoints(
      centerX: centerX,
      centerY: centerY,
      half: half,
    );
  }

  await connector.swipe(
    startX: endpoints.startX,
    startY: endpoints.startY,
    endX: endpoints.endX,
    endY: endpoints.endY,
  );
}

/// Swipe [distance] pixels from an explicit finger start, clamped to viewport.
({int startX, int startY, int endX, int endY}) swipeFromStart({
  required SwipeDirection direction,
  required int startX,
  required int startY,
  required int distance,
  required int maxX,
  required int maxY,
}) {
  final effectiveDistance = cappedSwipeDistanceFromStart(
    direction: direction,
    distance: distance,
    startX: startX,
    startY: startY,
    maxX: maxX,
    maxY: maxY,
  );

  return switch (direction) {
    SwipeDirection.up => (
        startX: startX,
        startY: startY,
        endX: startX,
        endY: startY - effectiveDistance,
      ),
    SwipeDirection.down => (
        startX: startX,
        startY: startY,
        endX: startX,
        endY: startY + effectiveDistance,
      ),
    SwipeDirection.left => (
        startX: startX,
        startY: startY,
        endX: startX - effectiveDistance,
        endY: startY,
      ),
    SwipeDirection.right => (
        startX: startX,
        startY: startY,
        endX: startX + effectiveDistance,
        endY: startY,
      ),
  };
}

/// Limits swipe distance so the finger end stays within the viewport.
int cappedSwipeDistanceFromStart({
  required SwipeDirection direction,
  required int distance,
  required int startX,
  required int startY,
  required int maxX,
  required int maxY,
}) {
  final maxDistance = switch (direction) {
    SwipeDirection.up => startY,
    SwipeDirection.down => maxY - startY,
    SwipeDirection.left => startX,
    SwipeDirection.right => maxX - startX,
  };
  return min(distance, maxDistance);
}

/// Limits swipe distance so finger endpoints stay within the viewport.
int cappedSwipeHalf({
  required SwipeDirection direction,
  required int half,
  required int centerX,
  required int centerY,
  required int maxX,
  required int maxY,
}) {
  final maxHalfX = min(centerX, maxX - centerX);
  final maxHalfY = min(centerY, maxY - centerY);
  return switch (direction) {
    SwipeDirection.up || SwipeDirection.down => min(half, maxHalfY),
    SwipeDirection.left || SwipeDirection.right => min(half, maxHalfX),
  };
}
