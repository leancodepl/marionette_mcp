import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/bridge_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import '../support/fake_native_connector.dart';

String _text(CallToolResult result) =>
    result.content.whereType<TextContent>().map((c) => c.text).join('\n');

/// iPhone 17 Pro Max: 440x956 points at scale 3.
const _iosMetrics = {
  'devicePixelRatio': 3.0,
  'physicalWidth': 1320.0,
  'physicalHeight': 2868.0,
  'logicalWidth': 440.0,
  'logicalHeight': 956.0,
};

void main() {
  group('mapFlutterRect (D13)', () {
    test('scales by the view size and offsets by its position', () {
      final mapped = mapFlutterRect(
        (
          view: const NativeBounds(x: 0, y: 0, width: 1080, height: 2028),
          logicalWidth: 1080 / 2.75,
          logicalHeight: 2028 / 2.75,
        ),
        x: 16,
        y: 100,
        width: 200,
        height: 50,
      );

      expect(mapped.scaleX, closeTo(2.75, 1e-9));
      expect(mapped.rect.toJson(),
          {'x': 44, 'y': 275, 'width': 550, 'height': 138});
      expect(mapped.center, (x: 319, y: 344));
    });

    test('a view that does not start at the top-left is offset', () {
      final mapped = mapFlutterRect(
        (
          view: const NativeBounds(x: 0, y: 100, width: 300, height: 600),
          logicalWidth: 100,
          logicalHeight: 200,
        ),
        x: 10,
        y: 10,
      );

      expect(mapped.center, (x: 30, y: 130));
    });
  });

  group('findFlutterView', () {
    test('Android: the largest android:id/content container', () {
      final view = findFlutterView([
        nativeElement(id: 'android:id/content', width: 800, height: 400),
        nativeElement(id: 'android:id/content', width: 1080, height: 2028),
        nativeElement(id: 'other', width: 2000, height: 3000),
      ], NativePlatform.android);

      expect(view?.toJson(), {'x': 0, 'y': 0, 'width': 1080, 'height': 2028});
    });

    test('iOS: the application element', () {
      final view = findFlutterView([
        nativeElement(type: 'XCUIElementTypeButton'),
        nativeElement(
          type: 'XCUIElementTypeApplication',
          width: 1320,
          height: 2868,
        ),
      ], NativePlatform.ios);

      expect(view?.width, 1320);
      expect(findFlutterView(const [], NativePlatform.ios), isNull);
    });
  });

  group('native_map_flutter_rect', () {
    Future<NativeServiceContext> contextWith(
      List<NativeElement> elements, {
      Future<Map<String, dynamic>> Function()? metrics,
      NativePlatform platform = NativePlatform.ios,
    }) async {
      final connector = FakeNativeConnector.single(elements)
        ..screen = const NativeScreen(width: 1320, height: 2868, scale: 3);
      final context = NativeServiceContext(
        connectorFactory: (platform, {serial, udid}) async => connector,
        flutterViewMetrics: metrics ?? () async => _iosMetrics,
      );
      await context.connect(platform);
      return context;
    }

    final app = nativeElement(
      type: 'XCUIElementTypeApplication',
      width: 1320,
      height: 2868,
    );

    test('maps bounds from get_interactive_elements to screenshot pixels',
        () async {
      final context = await contextWith([app]);

      final result = await handleNativeMapFlutterRect(
        context,
        {'x': 16, 'y': 300, 'width': 408, 'height': 200},
      );

      final payload = jsonDecode(_text(result)) as Map<String, dynamic>;
      expect(
          payload['rect'], {'x': 48, 'y': 900, 'width': 1224, 'height': 600});
      expect(payload['center'], {'x': 660, 'y': 1200});
      expect(payload['scale'], 3.0);
      expect(payload.containsKey('notes'), isFalse);
    });

    test('notes a missing or mismatched view and an off-screen point',
        () async {
      final missing = await contextWith(const []);
      final notes = (jsonDecode(_text(await handleNativeMapFlutterRect(
        missing,
        {'x': 10, 'y': 2000},
      ))) as Map<String, dynamic>)['notes'] as List;
      expect(notes.join(' '),
          allOf(contains('not found'), contains('outside the screen')));

      final mismatched = await contextWith([
        nativeElement(
          type: 'XCUIElementTypeApplication',
          width: 1000,
          height: 2868,
        ),
      ]);
      expect(
        _text(await handleNativeMapFlutterRect(mismatched, {'x': 1, 'y': 1})),
        contains('differs'),
      );
    });

    test('needs the Flutter lane and valid arguments', () async {
      final context = await contextWith(
        [app],
        metrics: () async => throw StateError('Not connected'),
      );

      expect(
        _text(await handleNativeMapFlutterRect(context, {'x': 1, 'y': 1})),
        contains('Connect the Flutter lane'),
      );
      final invalid = await handleNativeMapFlutterRect(context, {'x': 1});
      expect(invalid.isError, isTrue);
      expect(
        _text(await handleNativeMapFlutterRect(
          NativeServiceContext(),
          {'x': 1, 'y': 1},
        )),
        contains('native_connect'),
      );
    });
  });
}
