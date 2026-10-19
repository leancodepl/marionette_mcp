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
const _defaultMaxSwipes = 10;
const _maxMaxSwipes = 50;
const _defaultLongPressMs = 600;
const _defaultDoubleTapDelayMs = 100;
const _defaultSwipeDurationMs = 300;
const _maxGestureDurationMs = 10000;

/// Share of a `within` container's size a swipe may cover, so the finger
/// starts and ends inside it.
const _containerSwipeShare = 0.8;

/// Default share of a `within` container one search swipe covers. Lower
/// than [_containerSwipeShare]: iOS still adds some momentum (measured up to
/// 1.2× the finger distance for a slow drag), and the content must move by
/// less than one container height or the target could be skipped.
const _searchSwipeShare = 0.6;

/// A search swipe is a slow drag that rests before lifting, which keeps the
/// content close to where the finger stopped. A quick swipe flings: on iOS
/// one 300 ms swipe moved a list by more than twice the finger distance,
/// past the target, even with a 200 ms rest.
const _searchSwipeDurationMs = 1000;
const _searchHoldMs = 300;

/// Smallest distance between the two fingers of a pinch, in screenshot
/// pixels; closer fingers merge into one touch on some devices.
const _minPinchSpan = 60;

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

/// JSON schema properties for an x/y point in screenshot pixels.
Map<String, JsonSchema> _pointProperties(String purpose) => {
      'x': JsonSchema.number(
        description: 'X coordinate $purpose in screenshot pixels. Must be '
            'paired with y. Do not use Flutter logical coordinates.',
      ),
      'y': JsonSchema.number(
        description: 'Y coordinate $purpose in screenshot pixels. Must be '
            'paired with x.',
      ),
    };

/// Registers native tap, press, pinch, swipe and scroll tools.
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
          ..._pointProperties('to tap'),
        },
      ),
      callback: (args, extra) => handleNativeTap(context, args),
    )
    ..registerTool(
      'native_long_press',
      description:
          'Long-presses a native element (selector: text, textContains, id, '
          'type, optional index) or x+y in screenshot pixels, holding for '
          'durationMs (default $_defaultLongPressMs). Opens context menus, '
          'starts drag/reorder, or shows tooltips. '
          '$nativeSelectorRules '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Long Press'),
      inputSchema: ToolInputSchema(
        properties: {
          ...nativeSelectorProperties(),
          ..._pointProperties('to press'),
          'durationMs': JsonSchema.integer(
            description: 'How long to hold, in milliseconds (default '
                '$_defaultLongPressMs).',
          ),
        },
      ),
      callback: (args, extra) => handleNativeLongPress(context, args),
    )
    ..registerTool(
      'native_double_tap',
      description:
          'Double-taps a native element (selector: text, textContains, id, '
          'type, optional index) or x+y in screenshot pixels, with delayMs '
          '(default $_defaultDoubleTapDelayMs) between the taps. Zooms maps, '
          'images and web pages. '
          '$nativeSelectorRules '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Double Tap'),
      inputSchema: ToolInputSchema(
        properties: {
          ...nativeSelectorProperties(),
          ..._pointProperties('to tap'),
          'delayMs': JsonSchema.integer(
            description: 'Pause between the two taps in milliseconds '
                '(default $_defaultDoubleTapDelayMs; keep it under ~250).',
          ),
        },
      ),
      callback: (args, extra) => handleNativeDoubleTap(context, args),
    )
    ..registerTool(
      'native_pinch',
      description: 'Two-finger pinch on a native element (selector: text, '
          'textContains, id, type, optional index) or around x+y in '
          'screenshot pixels (default: screen center). scale > 1 spreads the '
          'fingers (zoom in), scale < 1 pinches them together (zoom out); '
          'the fingers start inside the element and move horizontally. The '
          'scale an app sees is approximate: it starts measuring after the '
          'fingers have moved a little. '
          '$nativeSelectorRules '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Pinch'),
      inputSchema: ToolInputSchema(
        properties: {
          'scale': JsonSchema.number(
            description: 'End distance between the fingers divided by the '
                'start distance, e.g. 2 (zoom in) or 0.5 (zoom out). Between '
                '0.1 and 10.',
          ),
          ...nativeSelectorProperties(),
          ..._pointProperties('of the pinch center'),
          'durationMs': JsonSchema.integer(
            description: 'Duration of the finger movement in milliseconds '
                '(default 500).',
          ),
        },
        required: ['scale'],
      ),
      callback: (args, extra) => handleNativePinch(context, args),
    )
    ..registerTool(
      'native_swipe',
      description: 'Swipes one finger from (startX, startY) to (endX, endY) in '
          'screenshot pixels over durationMs (default '
          '$_defaultSwipeDurationMs). Use for drags, sliders, and edge '
          'gestures (e.g. iOS back: start at x=1). For scrolling until '
          'something appears, use native_scroll. '
          '$nativeRoutingPreferFlutter '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Swipe'),
      inputSchema: ToolInputSchema(
        properties: {
          'startX': JsonSchema.number(description: 'Finger start X.'),
          'startY': JsonSchema.number(description: 'Finger start Y.'),
          'endX': JsonSchema.number(description: 'Finger end X.'),
          'endY': JsonSchema.number(description: 'Finger end Y.'),
          'durationMs': JsonSchema.integer(
            description: 'Movement duration in milliseconds (default '
                '$_defaultSwipeDurationMs). Longer is a slow drag; shorter '
                'a fling.',
          ),
        },
        required: ['startX', 'startY', 'endX', 'endY'],
      ),
      callback: (args, extra) => handleNativeSwipe(context, args),
    )
    ..registerTool(
      'native_scroll',
      description:
          'Performs a native swipe gesture. direction is the finger-swipe '
          'direction: ${SwipeDirection.commaSeparatedWireNames} (swipe up to '
          'see content below). Swipes from screen center by default; within '
          '(a selector of a scrollable container, e.g. a horizontal list) '
          'swipes inside that container instead; startX/startY set the '
          'finger start explicitly (screenshot pixels). Optional distance '
          'defaults to $_defaultSwipeDistance; within a container 80% of it '
          '(also the maximum), 60% while searching. Searching swipes are '
          'slow drags so the list does not fling past the target. '
          'If a target selector (text, textContains, id, type) is given, '
          'swipes repeatedly until a matching element is visible, up to '
          'maxSwipes (default $_defaultMaxSwipes), and stops early with an '
          'error when the content no longer moves (end of the list). '
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
          'within': JsonSchema.object(
            description: 'Selector of the container to swipe in (elements '
                'with scrollable: true in native_get_elements, or a list '
                'found by id). Same fields as other selectors.',
            properties: nativeSelectorProperties(),
          ),
          'maxSwipes': JsonSchema.integer(
            description: 'Maximum swipes while looking for the target '
                '(default $_defaultMaxSwipes, max $_maxMaxSwipes).',
          ),
          'distance': JsonSchema.number(
            description: 'Swipe distance in screenshot pixels '
                '(default: $_defaultSwipeDistance).',
          ),
          'startX': JsonSchema.number(
            description: 'Optional finger start X in screenshot pixels. '
                'Requires startY. Default: screen center. Not with within.',
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

/// Where a single-point gesture lands: an element chosen by a selector, or
/// explicit x/y coordinates.
final class _PointTarget {
  const _PointTarget._(this.selector, this.point);

  final NativeSelector selector;
  final ({int x, int y})? point;

  /// Parses a selector or x+y from [args]. Returns an error message for
  /// invalid combinations; with [optional], neither is accepted too.
  static ({_PointTarget? target, String? error}) parse(
    Map<String, dynamic> args,
    String tool, {
    bool optional = false,
  }) {
    final selector = nativeSelectorFromArgs(args);
    final coordinates = argPairPresence(args, 'x', 'y');
    final hasCoords = coordinates != ArgPairPresence.none;
    final hasSelector = !selector.isEmpty;

    String? error;
    if (hasSelector && hasCoords) {
      error = '$tool takes either a selector (text, textContains, id, type) '
          'or x and y — not both.';
    } else if (!hasSelector && !hasCoords && !optional) {
      error = '$tool requires either a selector (text, textContains, id, '
          'type) or both x and y.';
    } else if (coordinates == ArgPairPresence.partial) {
      error = '$tool coordinate mode requires both x and y.';
    } else if (!hasSelector && selector.index != null) {
      error = '$tool index requires a selector.';
    }
    if (error != null) return (target: null, error: error);

    final point =
        hasCoords ? (x: intArg(args, 'x')!, y: intArg(args, 'y')!) : null;
    return (target: _PointTarget._(selector, point), error: null);
  }

  bool get isEmpty => point == null && selector.isEmpty;

  /// The selected element, or null for coordinates / an empty target.
  Future<NativeElement?> element(NativeConnector connector) async =>
      selector.isEmpty
          ? null
          : selectElement(await connector.getNativeElements(), selector);

  String describe() {
    final p = point;
    if (p != null) return 'at (${p.x}, ${p.y})';
    return 'on native element ${selector.describe()}';
  }
}

/// Reads an optional positive duration argument, or returns an error.
({int? value, String? error}) _durationArg(
  Map<String, dynamic> args,
  String key, {
  int min = 1,
}) {
  final value = intArg(args, key);
  if (value != null && (value < min || value > _maxGestureDurationMs)) {
    return (
      value: null,
      error: 'Parameter "$key" must be between $min and '
          '$_maxGestureDurationMs.',
    );
  }
  return (value: value, error: null);
}

/// Handles `native_tap`.
Future<CallToolResult> handleNativeTap(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final parsed = _PointTarget.parse(args, 'native_tap');
  final target = parsed.target;
  if (target == null) return invalidArguments(parsed.error!);

  logger.info('Native tapping with args: $args');
  return runTool(logger, 'native tap', () async {
    final connector = context.requireConnector();

    final point = target.point;
    if (point != null) {
      await connector.tapAt(point.x, point.y);
      return CallToolResult(
        content: [
          TextContent(text: 'Successfully tapped at (${point.x}, ${point.y})'),
        ],
      );
    }

    await connector.tapElement((await target.element(connector))!);
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully tapped native element '
              '${target.selector.describe()}',
        ),
      ],
    );
  });
}

/// Handles `native_long_press`.
Future<CallToolResult> handleNativeLongPress(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final parsed = _PointTarget.parse(args, 'native_long_press');
  final target = parsed.target;
  if (target == null) return invalidArguments(parsed.error!);
  final duration = _durationArg(args, 'durationMs', min: 100);
  if (duration.error != null) return invalidArguments(duration.error!);
  final durationMs = duration.value ?? _defaultLongPressMs;

  logger.info('Native long press ${target.describe()} for ${durationMs}ms');
  return runTool(logger, 'native long press', () async {
    final connector = context.requireConnector();
    final point = target.point ?? (await target.element(connector))!.center;
    await connector.longPress(point.x, point.y, durationMs: durationMs);
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully long-pressed ${target.describe()} '
              '(${durationMs}ms)',
        ),
      ],
    );
  });
}

/// Handles `native_double_tap`.
Future<CallToolResult> handleNativeDoubleTap(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final parsed = _PointTarget.parse(args, 'native_double_tap');
  final target = parsed.target;
  if (target == null) return invalidArguments(parsed.error!);
  final delay = _durationArg(args, 'delayMs', min: 0);
  if (delay.error != null) return invalidArguments(delay.error!);
  final delayMs = delay.value ?? _defaultDoubleTapDelayMs;

  logger.info('Native double tap ${target.describe()} (delay ${delayMs}ms)');
  return runTool(logger, 'native double tap', () async {
    final connector = context.requireConnector();
    final point = target.point ?? (await target.element(connector))!.center;
    await connector.doubleTap(point.x, point.y, delayMs: delayMs);
    return CallToolResult(
      content: [
        TextContent(text: 'Successfully double-tapped ${target.describe()}'),
      ],
    );
  });
}

/// Handles `native_pinch`.
Future<CallToolResult> handleNativePinch(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final scale = (args['scale'] as num?)?.toDouble();
  if (scale == null || scale < 0.1 || scale > 10 || scale == 1) {
    return invalidArguments(
      'native_pinch requires scale between 0.1 and 10, other than 1 '
      '(> 1 zooms in, < 1 zooms out).',
    );
  }
  final parsed = _PointTarget.parse(args, 'native_pinch', optional: true);
  final target = parsed.target;
  if (target == null) return invalidArguments(parsed.error!);
  final duration = _durationArg(args, 'durationMs', min: 100);
  if (duration.error != null) return invalidArguments(duration.error!);

  final where = target.isEmpty ? 'at the screen center' : target.describe();
  logger.info('Native pinch $where (scale $scale)');
  return runTool(logger, 'native pinch', () async {
    final connector = context.requireConnector();
    final screen = await connector.getScreen();
    final element = await target.element(connector);
    final center = target.point ??
        element?.center ??
        (x: screen.width ~/ 2, y: screen.height ~/ 2);
    final spans = pinchSpans(
      scale: scale,
      centerX: center.x,
      screenWidth: screen.width,
      elementWidth: element?.bounds.width,
    );
    if (spans == null) {
      throw NativeOperationFailedException(
        'Not enough room for a pinch with scale $scale $where.',
        hint: 'Use a scale closer to 1, or pinch a larger element / '
            'closer to the screen center.',
      );
    }
    await connector.pinch(
      centerX: center.x,
      centerY: center.y,
      startSpan: spans.startSpan,
      endSpan: spans.endSpan,
      durationMs: duration.value ?? 500,
    );
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully pinched $where (scale $scale, fingers '
              '${spans.startSpan}px → ${spans.endSpan}px apart)',
        ),
      ],
    );
  });
}

/// Finger distances for a horizontal pinch of [scale] around [centerX].
///
/// Both fingers must stay on screen; they must also start inside the
/// element ([elementWidth]), because apps only receive touches that begin
/// on them. Uses 80% of the available room. Returns null when the closer
/// span would be under [_minPinchSpan].
({int startSpan, int endSpan})? pinchSpans({
  required double scale,
  required int centerX,
  required int screenWidth,
  int? elementWidth,
}) {
  final screenRoom = 2 * min(centerX, screenWidth - centerX) * 0.8;
  final startRoom = min(screenRoom, (elementWidth ?? screenWidth) * 0.8);
  final startSpan = scale > 1 ? min(startRoom, screenRoom / scale) : startRoom;
  final endSpan = startSpan * scale;
  if (min(startSpan, endSpan) < _minPinchSpan) return null;
  return (startSpan: startSpan.round(), endSpan: endSpan.round());
}

/// Handles `native_swipe`.
Future<CallToolResult> handleNativeSwipe(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final startX = intArg(args, 'startX');
  final startY = intArg(args, 'startY');
  final endX = intArg(args, 'endX');
  final endY = intArg(args, 'endY');
  if (startX == null || startY == null || endX == null || endY == null) {
    return invalidArguments(
      'native_swipe requires startX, startY, endX and endY.',
    );
  }
  final duration = _durationArg(args, 'durationMs');
  if (duration.error != null) return invalidArguments(duration.error!);
  final durationMs = duration.value ?? _defaultSwipeDurationMs;

  logger.info('Native swipe ($startX,$startY) → ($endX,$endY) '
      'in ${durationMs}ms');
  return runTool(logger, 'native swipe', () async {
    final connector = context.requireConnector();
    await connector.swipe(
      startX: startX,
      startY: startY,
      endX: endX,
      endY: endY,
      durationMs: durationMs,
    );
    return CallToolResult(
      content: [
        TextContent(
          text: 'Successfully swiped from ($startX, $startY) to '
              '($endX, $endY)',
        ),
      ],
    );
  });
}

/// Handles `native_scroll`. Search, settling, end-of-content detection and
/// `within` are described in docs/native-lane-decisions.md#d16.
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
  final maxSwipes = intArg(args, 'maxSwipes') ?? _defaultMaxSwipes;
  final rawWithin = args['within'];

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
  if (maxSwipes < 1 || maxSwipes > _maxMaxSwipes) {
    return invalidArguments(
      'Parameter "maxSwipes" must be between 1 and $_maxMaxSwipes.',
    );
  }
  if (rawWithin != null && rawWithin is! Map<String, dynamic>) {
    return invalidArguments(
      'Parameter "within" must be a selector object, e.g. '
      '{"id": "results_list"}.',
    );
  }
  final within = rawWithin == null
      ? null
      : nativeSelectorFromArgs(rawWithin as Map<String, dynamic>);
  if (within != null && within.isEmpty) {
    return invalidArguments(
      'Parameter "within" needs at least one of text, textContains, id, '
      'type.',
    );
  }
  if (within != null && startX != null) {
    return invalidArguments(
      'native_scroll takes either within or startX/startY, not both.',
    );
  }

  logger.info(
    'Native scrolling direction=${direction.wireName} '
    'target=${target.describe()} within=${within?.describe()} '
    'distance=$distance start=($startX,$startY)',
  );
  return runTool(logger, 'native scroll', () async {
    final connector = context.requireConnector();
    final screen = await connector.getScreen();

    var elements = within == null && target.isEmpty
        ? const <NativeElement>[]
        : await connector.getNativeElements();
    final container = within == null ? null : selectElement(elements, within);
    final area = container?.bounds ??
        NativeBounds(x: 0, y: 0, width: screen.width, height: screen.height);
    final endpoints = _scrollEndpoints(
      direction: direction,
      area: area,
      inContainer: container != null,
      searching: !target.isEmpty,
      distance: distance,
      startX: startX,
      startY: startY,
    );
    final inArea = container == null
        ? 'from screen center'
        : 'within '
            '${within!.describe()}';

    // While searching, a fling could carry the target past the viewport
    // between two reads; see [_searchSwipeDurationMs].
    Future<void> swipeOnce() => target.isEmpty
        ? connector.swipe(
            startX: endpoints.startX,
            startY: endpoints.startY,
            endX: endpoints.endX,
            endY: endpoints.endY,
          )
        : connector.swipe(
            startX: endpoints.startX,
            startY: endpoints.startY,
            endX: endpoints.endX,
            endY: endpoints.endY,
            durationMs: _searchSwipeDurationMs,
            holdMs: _searchHoldMs,
          );

    if (target.isEmpty) {
      await swipeOnce();
      final travelled = (endpoints.endX - endpoints.startX).abs() +
          (endpoints.endY - endpoints.startY).abs();
      return CallToolResult(
        content: [
          TextContent(
            text: 'Successfully swiped ${direction.wireName} $inArea '
                '(distance=$travelled)',
          ),
        ],
      );
    }

    var unchangedSwipes = 0;
    for (var swipes = 0;; swipes++) {
      if (elements.any((e) => e.isVisible && target.matches(e))) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'Found native element ${target.describe()} '
                  'after $swipes swipe(s)',
            ),
          ],
        );
      }
      if (swipes == maxSwipes) {
        throw NativeElementNotFoundException(
          '${target.describe()} after $maxSwipes swipe(s) '
          '${direction.wireName} $inArea',
          hint: 'Raise maxSwipes, try the opposite direction, or check the '
              'text with native_get_elements.',
        );
      }

      final before = _contentSignature(elements, area);
      await swipeOnce();
      elements = await _settledElements(connector, area);
      unchangedSwipes =
          _contentSignature(elements, area) == before ? unchangedSwipes + 1 : 0;
      if (unchangedSwipes == _endOfContentSwipes) {
        throw NativeElementNotFoundException(
          '${target.describe()}: reached the end of the content after '
          '${swipes + 1} swipe(s) ${direction.wireName} $inArea',
          hint: 'Try the opposite direction, or a within container if the '
              'target is in a nested list.',
        );
      }
    }
  });
}

/// Consecutive swipes without a visible change that mean the end of the
/// content. One is not enough: while a swipe crosses a large uniform area
/// (an empty block, a big image, a WebView spacer) the tree looks the same
/// although the content moved (docs/native-lane-decisions.md#d16).
const _endOfContentSwipes = 2;

/// Most UI-tree reads spent waiting for a fling to stop after a swipe.
const _maxSettleReads = 6;

/// The UI tree once the content of [area] has stopped moving: read until
/// two consecutive reads agree (bounded by [_maxSettleReads]).
///
/// Returning mid-fling would report positions that are already stale, and
/// on iOS a tap during scroll momentum only stops the scroll — it does not
/// press the button the agent was looking for.
Future<List<NativeElement>> _settledElements(
  NativeConnector connector,
  NativeBounds area,
) async {
  var elements = await connector.getNativeElements();
  for (var read = 1; read < _maxSettleReads; read++) {
    final next = await connector.getNativeElements();
    if (_contentSignature(next, area) == _contentSignature(elements, area)) {
      return next;
    }
    elements = next;
  }
  return elements;
}

/// Finger path for one `native_scroll` swipe inside [area].
({int startX, int startY, int endX, int endY}) _scrollEndpoints({
  required SwipeDirection direction,
  required NativeBounds area,
  required bool inContainer,
  required bool searching,
  required int? distance,
  required int? startX,
  required int? startY,
}) {
  final maxX = area.x + area.width;
  final maxY = area.y + area.height;
  if (startX != null && startY != null) {
    return swipeFromStart(
      direction: direction,
      startX: startX,
      startY: startY,
      distance: distance ?? _defaultSwipeDistance,
      maxX: maxX,
      maxY: maxY,
    );
  }

  final vertical =
      direction == SwipeDirection.up || direction == SwipeDirection.down;
  final span = vertical ? area.height : area.width;
  // Inside a container the swipe covers most of it by default: a fixed
  // 400 px moves a short list by only a couple of items per swipe.
  final containerMax = (span * _containerSwipeShare).round();
  final containerDefault =
      searching ? (span * _searchSwipeShare).round() : containerMax;
  final delta = inContainer
      ? min(distance ?? containerDefault, containerMax)
      : distance ?? _defaultSwipeDistance;

  final centerX = area.x + area.width ~/ 2;
  final centerY = area.y + area.height ~/ 2;
  final half = cappedSwipeHalf(
    direction: direction,
    half: delta ~/ 2,
    centerX: centerX - area.x,
    centerY: centerY - area.y,
    maxX: area.width,
    maxY: area.height,
  );
  return direction.swipeEndpoints(
    centerX: centerX,
    centerY: centerY,
    half: half,
  );
}

/// Identity of what is visible inside [area]: texts and positions of the
/// elements whose center lies in it. Unchanged after a swipe means the
/// content did not move — the end of the list.
String _contentSignature(List<NativeElement> elements, NativeBounds area) {
  final buffer = StringBuffer();
  for (final element in elements) {
    final c = element.center;
    if (!element.isVisible ||
        c.x < area.x ||
        c.y < area.y ||
        c.x >= area.x + area.width ||
        c.y >= area.y + area.height) {
      continue;
    }
    final b = element.bounds;
    buffer
      ..write(element.text ?? element.resourceId ?? element.className)
      ..write('@${b.x},${b.y};');
  }
  return buffer.toString();
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
