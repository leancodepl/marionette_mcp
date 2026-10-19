import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/arg_validation.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Largest difference, in screenshot pixels, between the Flutter view found
/// in the native tree and the physical size Flutter reports, before the
/// result carries a warning.
const _sizeTolerance = 4;

/// Registers tools that combine the Flutter and native lanes
/// (docs/native-lane-decisions.md#d13).
void registerNativeBridgeTools(
  McpServer server,
  NativeServiceContext context,
) {
  server.registerTool(
    'native_map_flutter_rect',
    description:
        'Converts a rectangle (or point) from the Flutter lane — the bounds '
        'of get_interactive_elements, in logical pixels of the Flutter view '
        '— to screenshot pixels of the native lane, for native gestures on '
        'something only Flutter can locate: a platform view (camera preview, '
        'map, video) that is invisible to native_get_elements. Returns rect '
        'and center in screenshot pixels; pass center to native_tap x/y, '
        'native_long_press, native_pinch etc. Never mix the two coordinate '
        'systems by hand. Requires both connect (Flutter lane) and '
        'native_connect.',
    annotations: const ToolAnnotations(
      title: 'Map Flutter Rect to Native',
      readOnlyHint: true,
    ),
    inputSchema: ToolInputSchema(
      properties: {
        'x': JsonSchema.number(description: 'Left, Flutter logical pixels.'),
        'y': JsonSchema.number(description: 'Top, Flutter logical pixels.'),
        'width': JsonSchema.number(
          description: 'Width in Flutter logical pixels (omit for a point).',
        ),
        'height': JsonSchema.number(
          description: 'Height in Flutter logical pixels (omit for a point).',
        ),
      },
      required: ['x', 'y'],
    ),
    callback: (args, extra) => handleNativeMapFlutterRect(context, args),
  );
}

/// Where the Flutter view is on screen and how big it is in logical pixels.
typedef FlutterViewPlacement = ({
  NativeBounds view,
  double logicalWidth,
  double logicalHeight,
});

/// Maps a rectangle in Flutter logical pixels to screenshot pixels.
///
/// The scale is the native view size divided by the logical view size, so
/// it also holds when the two lanes disagree about the density.
({NativeBounds rect, ({int x, int y}) center, double scaleX, double scaleY})
    mapFlutterRect(
  FlutterViewPlacement placement, {
  required double x,
  required double y,
  double width = 0,
  double height = 0,
}) {
  final view = placement.view;
  final scaleX = view.width / placement.logicalWidth;
  final scaleY = view.height / placement.logicalHeight;
  final left = view.x + x * scaleX;
  final top = view.y + y * scaleY;
  final rect = NativeBounds(
    x: left.round(),
    y: top.round(),
    width: (width * scaleX).round(),
    height: (height * scaleY).round(),
  );
  return (
    rect: rect,
    center: (
      x: (left + width * scaleX / 2).round(),
      y: (top + height * scaleY / 2).round(),
    ),
    scaleX: scaleX,
    scaleY: scaleY,
  );
}

/// The Flutter view in the native UI tree, in screenshot pixels: Android —
/// the app's `android:id/content` container, which the FlutterView fills
/// (the largest one, so a dialog's own content does not win); iOS — the
/// application window. Null when not found.
NativeBounds? findFlutterView(
  List<NativeElement> elements,
  NativePlatform platform,
) {
  switch (platform) {
    case NativePlatform.android:
      NativeBounds? best;
      for (final element in elements) {
        if (element.resourceId != 'android:id/content') continue;
        final b = element.bounds;
        if (best == null || b.width * b.height > best.width * best.height) {
          best = b;
        }
      }
      return best;
    case NativePlatform.ios:
      for (final element in elements) {
        if (element.className == 'XCUIElementTypeApplication') {
          return element.bounds;
        }
      }
      return null;
  }
}

/// Handles `native_map_flutter_rect`.
Future<CallToolResult> handleNativeMapFlutterRect(
  NativeServiceContext context,
  Map<String, dynamic> args,
) async {
  final x = (args['x'] as num?)?.toDouble();
  final y = (args['y'] as num?)?.toDouble();
  final width = (args['width'] as num?)?.toDouble() ?? 0;
  final height = (args['height'] as num?)?.toDouble() ?? 0;
  if (x == null || y == null) {
    return invalidArguments(
      'native_map_flutter_rect requires x and y (Flutter logical pixels).',
    );
  }
  if (width < 0 || height < 0) {
    return invalidArguments('width and height must not be negative.');
  }

  final logger = context.logger;
  logger.info('Mapping Flutter rect ($x, $y, ${width}x$height) to native');
  return runTool(logger, 'map flutter rect', () async {
    final connector = context.requireConnector();
    final readMetrics = context.flutterViewMetrics;
    if (readMetrics == null) {
      throw const NativeUnsupportedException(
        'The Flutter lane is not available in this server.',
      );
    }
    final Map<String, dynamic> metrics;
    try {
      metrics = await readMetrics();
    } catch (error) {
      throw NativeOperationFailedException(
        'Could not read the Flutter view metrics: $error',
        hint: 'Connect the Flutter lane with the connect tool (the app must '
            'use marionette_flutter with marionette.getViewMetrics).',
      );
    }
    final logicalWidth = (metrics['logicalWidth'] as num).toDouble();
    final logicalHeight = (metrics['logicalHeight'] as num).toDouble();
    final physicalWidth = (metrics['physicalWidth'] as num).toDouble();
    final physicalHeight = (metrics['physicalHeight'] as num).toDouble();

    final notes = <String>[];
    final screen = await connector.getScreen();
    var view = findFlutterView(
      await connector.getNativeElements(),
      context.platform ?? NativePlatform.android,
    );
    if (view == null) {
      view = NativeBounds(
        x: 0,
        y: 0,
        width: physicalWidth.round(),
        height: physicalHeight.round(),
      );
      notes.add('The Flutter view was not found in the native tree; assumed '
          'it starts at the top-left corner of the screen.');
    } else if ((view.width - physicalWidth).abs() > _sizeTolerance ||
        (view.height - physicalHeight).abs() > _sizeTolerance) {
      notes.add('The native view (${view.width}x${view.height}) differs from '
          "Flutter's physical size (${physicalWidth.round()}x"
          '${physicalHeight.round()}); mapped with the native size. Check '
          'the result with native_take_screenshot.');
    }

    final mapped = mapFlutterRect(
      (view: view, logicalWidth: logicalWidth, logicalHeight: logicalHeight),
      x: x,
      y: y,
      width: width,
      height: height,
    );
    final onScreen = mapped.center.x >= 0 &&
        mapped.center.y >= 0 &&
        mapped.center.x < screen.width &&
        mapped.center.y < screen.height;
    if (!onScreen) {
      notes.add('The center is outside the screen '
          '(${screen.width}x${screen.height}); scroll the element into view '
          'first.');
    }

    return CallToolResult(
      content: [
        TextContent(
          text: jsonEncode({
            'rect': mapped.rect.toJson(),
            'center': {'x': mapped.center.x, 'y': mapped.center.y},
            'scale': mapped.scaleX,
            'flutterView': view.toJson(),
            if (notes.isNotEmpty) 'notes': notes,
          }),
        ),
      ],
    );
  });
}
