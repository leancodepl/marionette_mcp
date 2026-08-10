import 'dart:math' show min;

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
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
  logging.Logger logger,
) {
  server
    ..registerTool(
      'native_tap',
      description:
          'Taps a native / system control by visible text, resource id / '
          'accessibility id, or physical-pixel coordinates. Match against '
          'elements from native_get_elements (exact text equality, exact id '
          'equality, or x+y). Provide exactly one matching mode: text, id, '
          'or both x and y. '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Tap'),
      inputSchema: ToolInputSchema(
        properties: {
          'text': JsonSchema.string(
            description: 'Exact visible text (or content-desc / label) of the '
                'element to tap, as returned by native_get_elements.',
          ),
          'id': JsonSchema.string(
            description:
                'Exact Android resource-id or iOS accessibility id of the '
                'element to tap, as returned in the "id" field of '
                'native_get_elements.',
          ),
          'x': JsonSchema.number(
            description:
                'Physical-pixel X coordinate to tap. Must be paired with y. '
                'Do not use Flutter logical coordinates.',
          ),
          'y': JsonSchema.number(
            description:
                'Physical-pixel Y coordinate to tap. Must be paired with x. '
                'Do not use Flutter logical coordinates.',
          ),
        },
      ),
      callback: (args, extra) async {
        final text = args['text'] as String?;
        final id = args['id'] as String?;
        final hasX = args.containsKey('x');
        final hasY = args.containsKey('y');
        final hasCoords = hasX || hasY;

        final modeCount = [
          text != null,
          id != null,
          hasCoords,
        ].where((e) => e).length;

        if (modeCount != 1) {
          return CallToolResult(
            isError: true,
            content: [
              const TextContent(
                text: 'native_tap requires exactly one matching mode: '
                    'text, id, or x+y.',
              ),
            ],
          );
        }

        if (hasCoords && (!hasX || !hasY)) {
          return CallToolResult(
            isError: true,
            content: [
              const TextContent(
                text: 'native_tap coordinate mode requires both x and y.',
              ),
            ],
          );
        }

        logger.info('Native tapping with args: $args');
        return runTool(logger, 'native tap', () async {
          final connector = context.requireConnector();

          if (hasCoords) {
            final x = (args['x'] as num).toInt();
            final y = (args['y'] as num).toInt();
            await connector.tapAt(x, y);
            return CallToolResult(
              content: [
                TextContent(text: 'Successfully tapped at ($x, $y)'),
              ],
            );
          }

          final elements = await connector.getNativeElements();
          final NativeElement match;
          if (text != null) {
            match = elements.firstWhere(
              (e) => e.text == text,
              orElse: () => throw StateError(
                'No native element with text="$text". '
                'Call native_get_elements and retry.',
              ),
            );
          } else {
            match = elements.firstWhere(
              (e) => e.resourceId == id,
              orElse: () => throw StateError(
                'No native element with id="$id". '
                'Call native_get_elements and retry.',
              ),
            );
          }

          await connector.tapElement(match);
          return CallToolResult(
            content: [
              TextContent(
                text: text != null
                    ? 'Successfully tapped native element text="$text"'
                    : 'Successfully tapped native element id="$id"',
              ),
            ],
          );
        });
      },
    )
    ..registerTool(
      'native_scroll',
      description:
          'Performs a native swipe gesture. direction is the finger-swipe '
          'direction: ${SwipeDirection.commaSeparatedWireNames}. Swipes from '
          'screen center by default; optional startX/startY set the finger '
          'start (physical pixels). Optional distance defaults to '
          '$_defaultSwipeDistance. '
          'If text is provided, repeatedly swipes until an element with that '
          'exact text is visible (max $_maxScrollAttempts attempts) or fails. '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Scroll'),
      inputSchema: ToolInputSchema(
        properties: {
          'direction': JsonSchema.string(
            description:
                'Finger-swipe direction: ${SwipeDirection.quotedWireNames}.',
          ),
          'text': JsonSchema.string(
            description:
                'Optional exact visible text to scroll until visible. When '
                'set, swipes repeatedly in direction until the text appears '
                'in native_get_elements.',
          ),
          'distance': JsonSchema.number(
            description: 'Swipe distance in physical pixels '
                '(default: $_defaultSwipeDistance).',
          ),
          'startX': JsonSchema.number(
            description: 'Optional finger start X in physical pixels. '
                'Requires startY. Default: horizontal/vertical center of '
                'inferred viewport.',
          ),
          'startY': JsonSchema.number(
            description: 'Optional finger start Y in physical pixels. '
                'Requires startX.',
          ),
        },
        required: ['direction'],
      ),
      callback: (args, extra) async {
        final direction = SwipeDirection.tryParse(
          args['direction'] as String?,
        );
        final text = args['text'] as String?;
        final distance = (args['distance'] as num?)?.toInt();
        final startX = (args['startX'] as num?)?.toInt();
        final startY = (args['startY'] as num?)?.toInt();

        if (direction == null) {
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'native_scroll requires direction to be '
                    '${SwipeDirection.quotedWireNames}.',
              ),
            ],
          );
        }

        if (distance != null && distance <= 0) {
          return CallToolResult(
            isError: true,
            content: [
              const TextContent(
                text: 'Parameter "distance" must be a positive integer.',
              ),
            ],
          );
        }

        if ((startX == null) != (startY == null)) {
          return CallToolResult(
            isError: true,
            content: [
              const TextContent(
                text: 'native_scroll requires both startX and startY when '
                    'either is provided.',
              ),
            ],
          );
        }

        logger.info(
          'Native scrolling direction=${direction.wireName} text=$text '
          'distance=$distance start=($startX,$startY)',
        );
        return runTool(logger, 'native scroll', () async {
          final connector = context.requireConnector();
          final delta = distance ?? _defaultSwipeDistance;

          if (text == null) {
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
            if (elements.any((e) => e.text == text)) {
              return CallToolResult(
                content: [
                  TextContent(
                    text: 'Found native element text="$text" '
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

          throw StateError(
            'Could not find native element text="$text" after '
            '$_maxScrollAttempts swipe(s) in direction=${direction.wireName}.',
          );
        });
      },
    );
}

Future<void> _swipeInDirection(
  NativeConnector connector,
  SwipeDirection direction,
  int distance, {
  int? startX,
  int? startY,
}) async {
  final elements = await connector.getNativeElements();
  var maxX = 0;
  var maxY = 0;
  for (final element in elements) {
    final right = element.bounds.x + element.bounds.width;
    final bottom = element.bounds.y + element.bounds.height;
    if (right > maxX) maxX = right;
    if (bottom > maxY) maxY = bottom;
  }
  if (maxX <= 0) maxX = 1080;
  if (maxY <= 0) maxY = 1920;

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
