import 'dart:math' show max, min;

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_selector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_runner.dart';
import 'package:marionette_mcp/src/native_service/tools/selector_args.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';

const _defaultSwipeDistance = 400;

/// `native_scroll`'s search limit when `maxSwipes` is not given.
const defaultMaxSwipes = 10;
const _maxMaxSwipes = 50;

/// `native_swipe`'s duration when `durationMs` is not given.
const defaultSwipeDurationMs = 300;
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

/// Finger-swipe direction for [native_scroll] (screen coordinates).
enum SwipeDirection {
  up(0, -1),
  down(0, 1),
  left(-1, 0),
  right(1, 0);

  const SwipeDirection(this.dx, this.dy);

  /// X of the unit vector in screen coordinates for this finger direction.
  final int dx;

  /// Y of the unit vector in screen coordinates for this finger direction.
  final int dy;

  /// Whether the finger moves along the Y axis.
  bool get isVertical => dx == 0;

  static String get _commaSeparatedNames =>
      values.map((direction) => direction.name).join(', ');

  static String get _quotedNames {
    final quoted = values.map((direction) => '"${direction.name}"').toList();
    return '${quoted.sublist(0, quoted.length - 1).join(', ')}, or ${quoted.last}';
  }

  ({int startX, int startY, int endX, int endY}) swipeEndpoints({
    required int centerX,
    required int centerY,
    required int half,
  }) {
    return (
      startX: centerX - dx * half,
      startY: centerY - dy * half,
      endX: centerX + dx * half,
      endY: centerY + dy * half,
    );
  }
}

/// JSON schema properties for an x/y point in screen pixels.
Map<String, JsonSchema> _pointProperties(String purpose) => {
      'x': JsonSchema.number(
        description: 'X coordinate $purpose in screen pixels. Must be '
            'paired with y. Do not use Flutter logical coordinates.',
      ),
      'y': JsonSchema.number(
        description: 'Y coordinate $purpose in screen pixels. Must be '
            'paired with x.',
      ),
    };

/// Registers native_tap, native_swipe and native_scroll.
void registerNativeGestureTools(
  LoggedMcpServer server,
  NativeServiceContext context,
) {
  server
    ..registerTool(
      'native_tap',
      description:
          'Taps a native / system control, chosen by a selector (text, '
          'textContains, id, type, optional index — values from '
          'native_get_elements) or by x+y coordinates in screen pixels '
          '(the units of the bounds in native_get_elements; a point read off '
          'native_take_screenshot needs the factor it reports). Use either a selector or x+y, not both. '
          '$nativeSelectorRules '
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
      'native_swipe',
      description: 'Swipes one finger from (startX, startY) to (endX, endY) in '
          'screen pixels over durationMs (default '
          '$defaultSwipeDurationMs). Use for drags, sliders, and edge '
          'gestures (e.g. iOS back: start at x=1). For scrolling until '
          'something appears, use native_scroll. '
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
                '$defaultSwipeDurationMs). Longer is a slow drag; shorter '
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
          'direction: ${SwipeDirection._commaSeparatedNames} (swipe up to '
          'see content below). Swipes from screen center by default; within '
          '(a selector of a scrollable container, e.g. a horizontal list) '
          'swipes inside that container instead; startX/startY set the '
          'finger start explicitly (screen pixels). Optional distance '
          'defaults to $_defaultSwipeDistance; within a container 80% of it '
          '(also the maximum), 60% while searching. Searching swipes are '
          'slow drags so the list does not fling past the target. '
          'If a target selector (text, textContains, id, type) is given, '
          'swipes repeatedly until a matching element is visible, up to '
          'maxSwipes (default $defaultMaxSwipes), and stops early with an '
          'error when the content no longer moves (end of the list). '
          'Requires native_connect.',
      annotations: const ToolAnnotations(title: 'Native Scroll'),
      inputSchema: ToolInputSchema(
        properties: {
          'direction': JsonSchema.string(
            description:
                'Finger-swipe direction: ${SwipeDirection._quotedNames}.',
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
                '(default $defaultMaxSwipes, max $_maxMaxSwipes).',
          ),
          'distance': JsonSchema.number(
            description: 'Swipe distance in screen pixels '
                '(default: $_defaultSwipeDistance).',
          ),
          'startX': JsonSchema.number(
            description: 'Optional finger start X in screen pixels. '
                'Requires startY. Default: screen center. Not with within.',
          ),
          'startY': JsonSchema.number(
            description: 'Optional finger start Y in screen pixels. '
                'Requires startX.',
          ),
        },
        required: ['direction'],
      ),
      callback: (args, extra) => handleNativeScroll(context, args),
    );
}

/// A parsed tool argument, or the message that rejects it.
sealed class _Parsed<T> {
  const _Parsed();
}

final class _Valid<T> extends _Parsed<T> {
  const _Valid(this.value);

  final T value;
}

final class _Invalid<T> extends _Parsed<T> {
  const _Invalid(this.message);

  final String message;
}

/// Where a single-point gesture lands: an element chosen by a selector, or
/// explicit x/y coordinates.
final class _PointTarget {
  const _PointTarget._(this.selector, this.point);

  final NativeSelector selector;
  final ({int x, int y})? point;

  /// Parses a selector or x+y from [args], or rejects an invalid
  /// combination.
  static _Parsed<_PointTarget> parse(
    Map<String, dynamic> args,
    String tool,
  ) {
    final selector = nativeSelectorFromArgs(args);
    final coordinates = argPairPresence(args, 'x', 'y');
    final hasCoords = coordinates != ArgPairPresence.none;
    final hasSelector = !selector.isEmpty;

    String? error;
    if (hasSelector && hasCoords) {
      error = '$tool takes either a selector (text, textContains, id, type) '
          'or x and y — not both.';
    } else if (!hasSelector && !hasCoords) {
      error = '$tool requires either a selector (text, textContains, id, '
          'type) or both x and y.';
    } else if (coordinates == ArgPairPresence.partial) {
      error = '$tool coordinate mode requires both x and y.';
    } else if (!hasSelector && selector.index != null) {
      error = '$tool index requires a selector.';
    }
    if (error != null) return _Invalid(error);
    if (!hasCoords) return _Valid(_PointTarget._(selector, null));

    return switch ((intArg(args, 'x'), intArg(args, 'y'))) {
      (final x?, final y?) => _Valid(_PointTarget._(selector, (x: x, y: y))),
      _ => _Invalid('$tool x and y must be numbers.'),
    };
  }
}

/// Reads an optional positive duration argument, or rejects it.
_Parsed<int?> _durationArg(Map<String, dynamic> args, String key) {
  final value = intArg(args, key);
  if (value != null && (value < 1 || value > _maxGestureDurationMs)) {
    return _Invalid(
      'Parameter "$key" must be between 1 and $_maxGestureDurationMs.',
    );
  }
  return _Valid(value);
}

/// Handles `native_tap`.
Future<CallToolResult> handleNativeTap(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final _PointTarget target;
  switch (_PointTarget.parse(args, 'native_tap')) {
    case _Invalid(:final message):
      return invalidArguments(message);
    case _Valid(:final value):
      target = value;
  }

  logger.info('Native tapping with args: $args');
  return runNativeTool(logger, 'native tap', () async {
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

    // A disabled element fails: a tap on it would do nothing, or land on a
    // sheet covering it.
    final element = await selectEnabledElement(connector, target.selector);
    await connector.tapElement(element);
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
  final int durationMs;
  switch (_durationArg(args, 'durationMs')) {
    case _Invalid(:final message):
      return invalidArguments(message);
    case _Valid(:final value):
      durationMs = value ?? defaultSwipeDurationMs;
  }

  logger.info('Native swipe ($startX,$startY) → ($endX,$endY) '
      'in ${durationMs}ms');
  return runNativeTool(logger, 'native swipe', () async {
    final connector = context.requireConnector();
    final screen = await connector.getScreen();
    if (!screen.bounds.contains(startX, startY)) {
      return invalidArguments(
        _startOffScreenMessage('native_swipe', (x: startX, y: startY), screen),
      );
    }
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

String _startOffScreenMessage(
  String tool,
  ({int x, int y}) start,
  NativeScreen screen,
) =>
    '$tool start point (${start.x}, ${start.y}) is outside the screen '
    'bounds (${screen.width}×${screen.height}).';

/// The parsed arguments of `native_scroll`.
final class _ScrollArguments {
  const _ScrollArguments({
    required this.direction,
    required this.target,
    required this.distance,
    required this.start,
    required this.maxSwipes,
    required this.within,
  });

  final SwipeDirection direction;
  final NativeSelector target;
  final int? distance;
  final ({int x, int y})? start;
  final int maxSwipes;
  final NativeSelector? within;
}

_Parsed<_ScrollArguments> _parseScrollArguments(
  Map<String, dynamic> args,
) {
  final direction = enumArg(args, 'direction', SwipeDirection.values);
  final target = nativeSelectorFromArgs(args);
  final distance = intArg(args, 'distance');
  final startX = intArg(args, 'startX');
  final startY = intArg(args, 'startY');
  final maxSwipes = intArg(args, 'maxSwipes') ?? defaultMaxSwipes;
  final rawWithin = args['within'];

  if (direction == null) {
    return _Invalid(
      'native_scroll requires direction to be ${SwipeDirection._quotedNames}.',
    );
  }

  String? error;
  if (distance != null && distance <= 0) {
    error = 'Parameter "distance" must be a positive integer.';
  } else if (argPairPresence(args, 'startX', 'startY') ==
      ArgPairPresence.partial) {
    error = 'native_scroll requires both startX and startY when either is '
        'provided.';
  } else if (maxSwipes < 1 || maxSwipes > _maxMaxSwipes) {
    error = 'Parameter "maxSwipes" must be between 1 and $_maxMaxSwipes.';
  } else if (rawWithin != null && rawWithin is! Map<String, dynamic>) {
    error = 'Parameter "within" must be a selector object, e.g. '
        '{"id": "results_list"}.';
  }
  if (error != null) return _Invalid(error);

  final within = rawWithin is Map<String, dynamic>
      ? nativeSelectorFromArgs(rawWithin)
      : null;
  if (within != null && within.isEmpty) {
    return const _Invalid(
      'Parameter "within" needs at least one of text, textContains, id, type.',
    );
  }
  if (within != null && startX != null) {
    return const _Invalid(
      'native_scroll takes either within or startX/startY, not both.',
    );
  }
  return _Valid(
    _ScrollArguments(
      direction: direction,
      target: target,
      distance: distance,
      start: startX != null && startY != null ? (x: startX, y: startY) : null,
      maxSwipes: maxSwipes,
      within: within,
    ),
  );
}

/// Handles `native_scroll`: search, settling, end-of-content detection and
/// `within`.
Future<CallToolResult> handleNativeScroll(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final logger = context.logger;
  final _ScrollArguments scroll;
  switch (_parseScrollArguments(args)) {
    case _Invalid(:final message):
      return invalidArguments(message);
    case _Valid(:final value):
      scroll = value;
  }

  logger.info(
    'Native scrolling direction=${scroll.direction.name} '
    'target=${scroll.target.describe()} within=${scroll.within?.describe()} '
    'distance=${scroll.distance} start=${scroll.start}',
  );
  return runNativeTool(logger, 'native scroll', () async {
    final connector = context.requireConnector();
    final screen = await connector.getScreen();
    if (scroll.start case final start?
        when !screen.bounds.contains(start.x, start.y)) {
      return invalidArguments(
          _startOffScreenMessage('native_scroll', start, screen));
    }

    final within = scroll.within;
    final elements = within == null && scroll.target.isEmpty
        ? const <NativeElement>[]
        : await connector.getNativeElements();
    final container = within == null ? null : selectElement(elements, within);
    final area = container?.bounds ?? screen.bounds;
    final endpoints = _scrollEndpoints(
      direction: scroll.direction,
      area: area,
      inContainer: container != null,
      searching: !scroll.target.isEmpty,
      distance: scroll.distance,
      start: scroll.start,
    );
    final inArea = switch ((within, scroll.start)) {
      (final selector?, _) => 'within ${selector.describe()}',
      (_, final start?) => 'from (${start.x}, ${start.y})',
      _ => 'from screen center',
    };

    if (scroll.target.isEmpty) {
      await connector.swipe(
        startX: endpoints.startX,
        startY: endpoints.startY,
        endX: endpoints.endX,
        endY: endpoints.endY,
      );
      final travelled = (endpoints.endX - endpoints.startX).abs() +
          (endpoints.endY - endpoints.startY).abs();
      return CallToolResult(
        content: [
          TextContent(
            text: 'Successfully swiped ${scroll.direction.name} $inArea '
                '(distance=$travelled)',
          ),
        ],
      );
    }

    return _scrollUntilFound(
      connector,
      scroll,
      elements: elements,
      area: area,
      endpoints: endpoints,
      inArea: inArea,
    );
  });
}

/// Swipes slowly until [scroll]'s target is visible in [elements], the
/// search limit is reached, or the content of [area] stops moving.
Future<CallToolResult> _scrollUntilFound(
  NativeConnector connector,
  _ScrollArguments scroll, {
  required List<NativeElement> elements,
  required NativeBounds area,
  required ({int startX, int startY, int endX, int endY}) endpoints,
  required String inArea,
}) async {
  final target = scroll.target;
  var current = elements;
  var unchangedSwipes = 0;
  for (var swipes = 0;; swipes++) {
    if (current.any((e) => e.isVisible && target.matches(e))) {
      return CallToolResult(content: [
        TextContent(
          text:
              'Found native element ${target.describe()} after $swipes swipe(s)',
        ),
      ]);
    }
    if (swipes == scroll.maxSwipes) {
      throw NativeElementNotFoundException(
        '${target.describe()} after ${scroll.maxSwipes} swipe(s) '
        '${scroll.direction.name} $inArea',
        hint: 'Raise maxSwipes, try the opposite direction, or check the '
            'text with native_get_elements.',
      );
    }
    final before = _contentSignature(current, area);
    await connector.swipe(
      startX: endpoints.startX,
      startY: endpoints.startY,
      endX: endpoints.endX,
      endY: endpoints.endY,
      durationMs: _searchSwipeDurationMs,
      holdMs: _searchHoldMs,
    );
    current = await _settledElements(connector, area);
    unchangedSwipes =
        _contentSignature(current, area) == before ? unchangedSwipes + 1 : 0;
    if (unchangedSwipes == _endOfContentSwipes) {
      throw NativeElementNotFoundException(
        '${target.describe()}: reached the end of the content after '
        '${swipes + 1} swipe(s) ${scroll.direction.name} $inArea',
        hint: 'Try the opposite direction, or a within container if the '
            'target is in a nested list.',
      );
    }
  }
}

/// Consecutive swipes without a visible change that mean the end of the
/// content. One is not enough: while a swipe crosses a large uniform area
/// (an empty block, a big image, a WebView spacer) the tree looks the same
/// although the content moved.
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
  required ({int x, int y})? start,
}) {
  if (start != null) {
    return swipeFromStart(
      direction: direction,
      startX: start.x,
      startY: start.y,
      distance: distance ?? _defaultSwipeDistance,
      maxX: area.x + area.width,
      maxY: area.y + area.height,
    );
  }

  final span = direction.isVertical ? area.height : area.width;
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
    final center = element.center;
    if (!element.isVisible || !area.contains(center.x, center.y)) continue;
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
  return (
    startX: startX,
    startY: startY,
    endX: startX + direction.dx * effectiveDistance,
    endY: startY + direction.dy * effectiveDistance,
  );
}

/// Limits swipe distance so the finger end stays within the viewport. A
/// start already past the edge in [direction] gives 0.
int cappedSwipeDistanceFromStart({
  required SwipeDirection direction,
  required int distance,
  required int startX,
  required int startY,
  required int maxX,
  required int maxY,
}) {
  final (start, limit) = direction.isVertical ? (startY, maxY) : (startX, maxX);
  final towardsLimit = direction.dx + direction.dy > 0;
  final room = towardsLimit ? limit - start : start;
  return max(0, min(distance, room));
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
  final axisLimit = direction.isVertical
      ? min(centerY, maxY - centerY)
      : min(centerX, maxX - centerX);
  return min(half, axisLimit);
}
