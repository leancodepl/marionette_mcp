import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/mcp/tools/ancestor_keys_description.dart';
import 'package:marionette_mcp/src/mcp/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'base_tool.dart';
import 'tool_results.dart';

/// MCP tool `tap`.
class TapTool extends BaseTool {
  TapTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'tap';

  @override
  String get description =>
      'Simulates a tap gesture on an element in the Flutter app that matches the given criteria. You can match elements by their key (a ValueKey<String>), by their Semantics identifier, by their text content (but not accessibility label!), by their widget type, or by screen coordinates. Only one matching method should be used: either key, identifier, text, type, or coordinates. Prefer using the key if available, as it is more reliable; the Semantics identifier is the next-best stable selector. Limit yourself to elements from get_interactive_elements only if you can. Tapping a text field gives it focus, after which you can use enter_text with focused_element to type into it. Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Tap Element');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The key of the element to tap. You can get the key of an element by calling get_interactive_elements.',
          ),
          'identifier': JsonSchema.string(
            description:
                'The Semantics identifier of the element to tap. A stable, '
                'unique, accessibility identifier set via Semantics(identifier: ...). '
                'Useful when an element has no ValueKey but does set an identifier. '
                'You can discover identifiers by calling get_interactive_elements.',
          ),
          'text': JsonSchema.string(
            description:
                'The visible text content of the element to tap. Use this for elements that display text like buttons or labels.',
          ),
          'type': JsonSchema.string(
            description:
                'The widget type name of the element to tap (e.g., "ElevatedButton", "IconButton"). Use this to match elements by their Flutter widget type.',
          ),
          'coordinates': JsonSchema.object(
            description:
                'Screen coordinates to tap at. Use this to tap at a specific position on the screen.',
            properties: {
              'x': JsonSchema.number(
                description:
                    'The x coordinate (horizontal position from left).',
              ),
              'y': JsonSchema.number(
                description: 'The y coordinate (vertical position from top).',
              ),
            },
            required: ['x', 'y'],
          ),
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: ancestorKeysDescription,
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final matcher = buildMatcher(args);
    logger.info('Tapping with matcher: $matcher');
    return runTool(logger, 'tap', () async {
      final response = await connector.tap(matcher);
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully tapped');
    });
  }
}

/// MCP tool `secondary_tap`.
class SecondaryTapTool extends BaseTool {
  SecondaryTapTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'secondary_tap';

  @override
  String get description =>
      'Simulates a secondary tap (right mouse button click) on an element in the Flutter app. Desktop only — dispatches a mouse pointer with the secondary button pressed, which is what Flutter recognises as onSecondaryTap (e.g. for opening context menus). You can match elements by their key (a ValueKey<String>), by their Semantics identifier, by their text content, by their widget type, or by screen coordinates. Only one matching method should be used. Prefer using the key if available, as it is more reliable. Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Secondary Tap Element');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The key of the element to secondary tap. You can get the key of an element by calling get_interactive_elements.',
          ),
          'identifier': JsonSchema.string(
            description:
                'The Semantics identifier of the element to secondary tap. A '
                'stable, unique accessibility identifier set via '
                'Semantics(identifier: ...).',
          ),
          'text': JsonSchema.string(
            description:
                'The visible text content of the element to secondary tap.',
          ),
          'type': JsonSchema.string(
            description:
                'The widget type name of the element to secondary tap (e.g., "ElevatedButton", "ListTile").',
          ),
          'coordinates': JsonSchema.object(
            description: 'Screen coordinates to secondary tap at.',
            properties: {
              'x': JsonSchema.number(
                description:
                    'The x coordinate (horizontal position from left).',
              ),
              'y': JsonSchema.number(
                description: 'The y coordinate (vertical position from top).',
              ),
            },
            required: ['x', 'y'],
          ),
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: ancestorKeysDescription,
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final matcher = buildMatcher(args);
    logger.info('Secondary tapping with matcher: $matcher');
    return runTool(logger, 'secondary tap', () async {
      final response = await connector.secondaryTap(matcher);
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully secondary tapped');
    });
  }
}

/// MCP tool `double_tap`.
class DoubleTapTool extends BaseTool {
  DoubleTapTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'double_tap';

  @override
  String get description =>
      'Simulates a double tap gesture on an element in the Flutter app. This is useful for triggering text selection, zoom, or any widget that responds to double tap. You can match elements by their key, identifier, text, type, or coordinates. An optional delay parameter controls the time between the two taps (default: 100ms). Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Double Tap Element');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The key of the element to double tap. You can get the key of an element by calling get_interactive_elements.',
          ),
          'identifier': JsonSchema.string(
            description:
                'The Semantics identifier of the element to double tap. A '
                'stable, unique accessibility identifier set via '
                'Semantics(identifier: ...).',
          ),
          'text': JsonSchema.string(
            description:
                'The visible text content of the element to double tap.',
          ),
          'type': JsonSchema.string(
            description:
                'The widget type name of the element to double tap (e.g., "ListTile", "Card").',
          ),
          'coordinates': JsonSchema.object(
            description: 'Screen coordinates to double tap at.',
            properties: {
              'x': JsonSchema.number(
                description:
                    'The x coordinate (horizontal position from left).',
              ),
              'y': JsonSchema.number(
                description: 'The y coordinate (vertical position from top).',
              ),
            },
            required: ['x', 'y'],
          ),
          'delay': JsonSchema.number(
            description:
                'Time between the two taps in milliseconds. Defaults to 100ms which is within Flutter\'s double-tap recognition window (40ms-300ms).',
          ),
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: ancestorKeysDescription,
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final delay = (args['delay'] as num?)?.toInt();
    if (delay != null && delay <= 0) {
      return CallToolResult(
        isError: true,
        content: [
          const TextContent(
            text: 'Parameter "delay" must be a positive integer.',
          ),
        ],
      );
    }
    final matcher = buildMatcher(args);
    logger.info('Double tapping with matcher: $matcher');
    return runTool(logger, 'double tap', () async {
      final response = await connector.doubleTap(matcher, delayMs: delay);
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully double tapped');
    });
  }
}

/// MCP tool `long_press`.
class LongPressTool extends BaseTool {
  LongPressTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'long_press';

  @override
  String get description =>
      'Simulates a long press gesture on an element in the Flutter app. This is useful for triggering context menus, reorderable lists, or any widget that responds to long press. You can match elements by their key, identifier, text, type, or coordinates. An optional duration parameter controls how long the press is held (default: 600ms). Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Long Press Element');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The key of the element to long press. You can get the key of an element by calling get_interactive_elements.',
          ),
          'identifier': JsonSchema.string(
            description:
                'The Semantics identifier of the element to long press. A '
                'stable, unique accessibility identifier set via '
                'Semantics(identifier: ...).',
          ),
          'text': JsonSchema.string(
            description:
                'The visible text content of the element to long press.',
          ),
          'type': JsonSchema.string(
            description:
                'The widget type name of the element to long press (e.g., "ListTile", "Card").',
          ),
          'coordinates': JsonSchema.object(
            description: 'Screen coordinates to long press at.',
            properties: {
              'x': JsonSchema.number(
                description:
                    'The x coordinate (horizontal position from left).',
              ),
              'y': JsonSchema.number(
                description: 'The y coordinate (vertical position from top).',
              ),
            },
            required: ['x', 'y'],
          ),
          'duration': JsonSchema.number(
            description:
                'How long to hold the press in milliseconds. Defaults to 600ms which matches Flutter\'s long press behavior.',
          ),
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: ancestorKeysDescription,
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final duration = (args['duration'] as num?)?.toInt();
    final matcher = buildMatcher(args);
    logger.info('Long pressing with matcher: $matcher');
    return runTool(logger, 'long press', () async {
      final response = await connector.longPress(matcher, durationMs: duration);
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully long pressed');
    });
  }
}

/// MCP tool `swipe`.
class SwipeTool extends BaseTool {
  SwipeTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'swipe';

  @override
  String get description =>
      'Simulates a swipe/drag gesture on the Flutter app. Supports two modes: '
      '1. Element-based: provide key, identifier, or text to identify the element, plus a direction (left, right, up, down) and optional distance in pixels (default 200). '
      '2. Coordinate-based: provide startX, startY, endX, endY for precise control. '
      'Useful for interacting with PageView, Dismissible, Drawer, Slider, and other swipe-based widgets. '
      'Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations => const ToolAnnotations(title: 'Swipe');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The key of the element to swipe on. Use with direction.',
          ),
          'identifier': JsonSchema.string(
            description:
                'The Semantics identifier of the element to swipe on. Use with '
                'direction. A stable, unique accessibility identifier set via '
                'Semantics(identifier: ...).',
          ),
          'text': JsonSchema.string(
            description:
                'The visible text content of the element to swipe on. Use with direction.',
          ),
          'direction': JsonSchema.string(
            description:
                'Swipe direction when using element-based mode: left, right, up, or down.',
          ),
          'distance': JsonSchema.number(
            description:
                'Swipe distance in pixels for element-based mode (default: 200).',
          ),
          'startX': JsonSchema.number(
            description: 'Start X coordinate for coordinate-based swipe.',
          ),
          'startY': JsonSchema.number(
            description: 'Start Y coordinate for coordinate-based swipe.',
          ),
          'endX': JsonSchema.number(
            description: 'End X coordinate for coordinate-based swipe.',
          ),
          'endY': JsonSchema.number(
            description: 'End Y coordinate for coordinate-based swipe.',
          ),
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: ancestorKeysDescription,
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    logger.info('Swiping with args: $args');

    final swipeArgs = <String, dynamic>{};

    if (args.containsKey('startX')) {
      if (!args.containsKey('startY') ||
          !args.containsKey('endX') ||
          !args.containsKey('endY')) {
        return CallToolResult(
          isError: true,
          content: [
            const TextContent(
              text: 'Coordinate-based swipe requires all of: '
                  'startX, startY, endX, endY',
            ),
          ],
        );
      }
      swipeArgs['startX'] = args['startX'].toString();
      swipeArgs['startY'] = args['startY'].toString();
      swipeArgs['endX'] = args['endX'].toString();
      swipeArgs['endY'] = args['endY'].toString();
    } else {
      if (!args.containsKey('direction')) {
        return CallToolResult(
          isError: true,
          content: [
            const TextContent(
              text: 'Element-based swipe requires a direction '
                  '(left, right, up, or down).',
            ),
          ],
        );
      }
      swipeArgs.addAll(buildMatcher(args));
      swipeArgs['direction'] = args['direction'] as String;
      if (args.containsKey('distance')) {
        swipeArgs['distance'] = args['distance'].toString();
      }
    }

    return runTool(logger, 'swipe', () async {
      final response = await connector.swipe(swipeArgs);
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully swiped');
    });
  }
}

/// MCP tool `pinch_zoom`.
class PinchZoomTool extends BaseTool {
  PinchZoomTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'pinch_zoom';

  @override
  String get description =>
      'Simulates a pinch zoom gesture on an element in the Flutter app. '
      'Use scale > 1.0 to zoom in (fingers move apart) and scale < 1.0 '
      'to zoom out (fingers move together). You can target the element by '
      'key, identifier, text, type, or coordinates. Useful for maps, '
      'images, PDFs, and other zoomable content. '
      'Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations => const ToolAnnotations(title: 'Pinch Zoom');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description: 'The key of the element to pinch zoom on.',
          ),
          'identifier': JsonSchema.string(
            description:
                'The Semantics identifier of the element to pinch zoom on. A '
                'stable, unique accessibility identifier set via '
                'Semantics(identifier: ...).',
          ),
          'text': JsonSchema.string(
            description:
                'The visible text content of the element to pinch zoom on.',
          ),
          'type': JsonSchema.string(
            description:
                'The widget type name of the element to pinch zoom on.',
          ),
          'coordinates': JsonSchema.object(
            description: 'Screen coordinates to pinch zoom at.',
            properties: {
              'x': JsonSchema.number(description: 'The x coordinate.'),
              'y': JsonSchema.number(description: 'The y coordinate.'),
            },
            required: ['x', 'y'],
          ),
          'scale': JsonSchema.number(
            description:
                'Zoom scale factor. Values > 1.0 zoom in, values < 1.0 '
                'zoom out. For example, 2.0 doubles the zoom level.',
          ),
          'start_distance': JsonSchema.number(
            description: 'Initial distance between the two fingers in pixels '
                '(default: 200).',
          ),
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: ancestorKeysDescription,
          ),
        },
        required: ['scale'],
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final matcher = buildMatcher(args);
    if (!hasSelector(matcher)) {
      return CallToolResult(
        isError: true,
        content: [
          const TextContent(
            text: 'Missing required selector: provide "key", '
                '"identifier", "text", "type", or "coordinates".',
          ),
        ],
      );
    }
    final scale = (args['scale'] as num).toDouble();
    if (scale <= 0) {
      return CallToolResult(
        isError: true,
        content: [const TextContent(text: 'scale must be a positive number.')],
      );
    }
    final startDistance = (args['start_distance'] as num?)?.toDouble();
    if (startDistance != null && startDistance <= 0) {
      return CallToolResult(
        isError: true,
        content: [
          const TextContent(text: 'start_distance must be a positive number.'),
        ],
      );
    }

    logger.info('Pinch zooming with matcher: $matcher, scale: $scale');
    return runTool(logger, 'pinch zoom', () async {
      final response = await connector.pinchZoom(
        matcher,
        scale: scale,
        startDistance: startDistance,
      );
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully pinch zoomed');
    });
  }
}

/// MCP tool `press_back_button`.
class PressBackButtonTool extends BaseTool {
  PressBackButtonTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'press_back_button';

  @override
  String get description =>
      'Simulates a system back button press in the Flutter app. '
      'This triggers the same mechanism as the Android back button or '
      'iOS swipe-back gesture. If the app has a route to pop, it will '
      'be popped. If the app is on the root route, the system may '
      'minimize or close the app (same as real back button behavior). '
      'Works with Navigator, GoRouter, and other routing solutions. '
      'Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Press Back Button');

  @override
  ToolOutputSchema get outputSchema => ToolOutputSchema(
        properties: {
          'message': JsonSchema.string(),
          'didPop': JsonSchema.boolean(),
        },
        required: ['message'],
      );

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    logger.info('Pressing back button');
    return runTool(logger, 'press back button', () async {
      final response = await connector.pressBackButton();
      final message = response['message'] as String?;
      final didPop = response['didPop'];

      return messageResult(
        message ??
            (didPop == true
                ? 'Back button pressed, route was popped'
                : 'Back button pressed, no route to pop'),
        fields: {if (didPop is bool) 'didPop': didPop},
      );
    });
  }
}

/// MCP tool `scroll_to`.
class ScrollToTool extends BaseTool {
  ScrollToTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'scroll_to';

  @override
  String get description =>
      'Scrolls the view until an element matching the given criteria becomes visible. You can match elements by their key (a ValueKey<String>), by their Semantics identifier, or by their visible text content. This is useful when you need to interact with elements that are not currently visible on screen. Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Scroll to Element');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'key': JsonSchema.string(
            description:
                'The key of the element to scroll to. You can get the key of an element by calling get_interactive_elements.',
          ),
          'identifier': JsonSchema.string(
            description:
                'The Semantics identifier of the element to scroll to. A '
                'stable, unique accessibility identifier set via '
                'Semantics(identifier: ...).',
          ),
          'text': JsonSchema.string(
            description:
                'The visible text content of the element to scroll to.',
          ),
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: ancestorKeysDescription,
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final matcher = buildMatcher(args);
    logger.info('Scrolling to element with matcher: $matcher');
    return runTool(logger, 'scroll to element', () async {
      final response = await connector.scrollToElement(matcher);
      final message = response['message'] as String?;
      return messageResult(message ?? 'Successfully scrolled to element');
    });
  }
}
