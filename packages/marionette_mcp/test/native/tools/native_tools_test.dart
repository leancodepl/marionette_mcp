import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/connection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/screenshot_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/text_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import '../support/fake_native_connector.dart';

String _text(CallToolResult result) =>
    result.content.whereType<TextContent>().map((c) => c.text).join('\n');

Matcher _isToolError(Object textMatcher) => isA<CallToolResult>()
    .having((r) => r.isError, 'isError', isTrue)
    .having(_text, 'text', textMatcher);

Matcher _isToolSuccess(Object textMatcher) => isA<CallToolResult>()
    .having((r) => r.isError, 'isError', isFalse)
    .having(_text, 'text', textMatcher);

NativeServiceContext _contextWith(NativeConnector connector) =>
    NativeServiceContext()..connector = connector;

void main() {
  group('native_connect', () {
    test('rejects an unknown platform without connecting', () async {
      var factoryCalls = 0;
      final context = NativeServiceContext(
        connectorFactory: (platform, {serial, udid}) async {
          factoryCalls++;
          return FakeNativeConnector();
        },
      );

      final result = await handleNativeConnect(context, {'platform': 'web'});

      expect(result, _isToolError(contains('"android" or "ios"')));
      expect(factoryCalls, 0);
    });

    test('connects and reports the platform', () async {
      final context = NativeServiceContext(
        connectorFactory: (platform, {serial, udid}) async {
          expect(platform, NativePlatform.ios);
          expect(udid, 'SIM-1');
          return FakeNativeConnector();
        },
      );

      final result = await handleNativeConnect(
        context,
        {'platform': 'iOS', 'udid': 'SIM-1'},
      );

      expect(result, _isToolSuccess(contains('platform=ios')));
      expect(context.connector, isNotNull);
    });

    test('reports a failed connect and stays disconnected', () async {
      final context = NativeServiceContext(
        connectorFactory: (platform, {serial, udid}) =>
            Future<NativeConnector>.error(StateError('adb exploded')),
      );

      final result =
          await handleNativeConnect(context, {'platform': 'android'});

      expect(result, _isToolError(contains('adb exploded')));
      expect(context.connector, isNull);
    });
  });

  group('native_disconnect', () {
    test('disposes the session', () async {
      final connector = FakeNativeConnector();
      final context = _contextWith(connector);

      final result = await handleNativeDisconnect(context);

      expect(result, _isToolSuccess(contains('disconnected')));
      expect(connector.disposeCalls, 1);
      expect(context.connector, isNull);
    });
  });

  group('session-bound tools without native_connect', () {
    final calls =
        <String, Future<CallToolResult> Function(NativeServiceContext)>{
      'native_get_elements': handleNativeGetElements,
      'native_take_screenshot': handleNativeTakeScreenshot,
      'native_tap': (c) => handleNativeTap(c, {'text': 'OK'}),
      'native_scroll': (c) => handleNativeScroll(c, {'direction': 'up'}),
      'native_enter_text': (c) =>
          handleNativeEnterText(c, {'text': 'x', 'id': 'field'}),
    };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      test('$name tells the agent to call native_connect', () async {
        expect(
          await call(NativeServiceContext()),
          _isToolError(contains('native_connect')),
        );
      });
    }
  });

  group('native_get_elements', () {
    test('returns elements and foregroundApp as JSON', () async {
      final context = _contextWith(
        FakeNativeConnector.single([nativeElement(text: 'Allow', id: 'allow')]),
      );

      final result = await handleNativeGetElements(context);
      final payload = jsonDecode(_text(result)) as Map<String, dynamic>;

      expect(payload['foregroundApp'], 'com.example.app');
      expect(payload['elements'], [
        {
          'type': 'android.widget.Button',
          'text': 'Allow',
          'id': 'allow',
          'bounds': {'x': 0, 'y': 0, 'width': 100, 'height': 50},
          'clickable': true,
        },
      ]);
    });

    test('reports null foregroundApp instead of failing', () async {
      final context = _contextWith(
        FakeNativeConnector(foregroundAppError: StateError('no adb')),
      );

      final result = await handleNativeGetElements(context);

      expect(result.isError, isFalse);
      expect(
        (jsonDecode(_text(result)) as Map<String, dynamic>)['foregroundApp'],
        isNull,
      );
    });

    test('propagates tree errors', () async {
      final context = _contextWith(
        FakeNativeConnector(error: StateError('session gone')),
      );

      expect(
        await handleNativeGetElements(context),
        _isToolError(contains('session gone')),
      );
    });
  });

  group('native_tap', () {
    test('requires exactly one matching mode', () async {
      final context = _contextWith(FakeNativeConnector());

      for (final args in <Map<String, dynamic>>[
        {},
        {'text': 'OK', 'id': 'ok'},
        {'text': 'OK', 'x': 1, 'y': 2},
      ]) {
        expect(
          await handleNativeTap(context, args),
          _isToolError(contains('exactly one matching mode')),
          reason: '$args',
        );
      }
    });

    test('requires both x and y', () async {
      expect(
        await handleNativeTap(_contextWith(FakeNativeConnector()), {'x': 1}),
        _isToolError(contains('both x and y')),
      );
    });

    test('taps coordinates', () async {
      final connector = FakeNativeConnector();

      final result = await handleNativeTap(
        _contextWith(connector),
        {'x': 10.7, 'y': 20},
      );

      expect(result, _isToolSuccess('Successfully tapped at (10, 20)'));
      expect(connector.taps, [(x: 10, y: 20)]);
    });

    test('taps the first element with matching text or id', () async {
      final allow = nativeElement(text: 'Allow', id: 'allow');
      final deny = nativeElement(text: 'Deny', id: 'deny');
      final connector = FakeNativeConnector.single([allow, deny]);
      final context = _contextWith(connector);

      await handleNativeTap(context, {'text': 'Deny'});
      await handleNativeTap(context, {'id': 'allow'});

      expect(connector.tappedElements, [deny, allow]);
    });

    test('reports a missing element with a hint', () async {
      expect(
        await handleNativeTap(
          _contextWith(FakeNativeConnector()),
          {'text': 'Nope'},
        ),
        _isToolError(
          allOf(contains('text="Nope"'), contains('native_get_elements')),
        ),
      );
    });
  });

  group('native_scroll', () {
    test('validates direction, distance and start point', () async {
      final context = _contextWith(FakeNativeConnector());

      expect(
        await handleNativeScroll(context, {'direction': 'diagonal'}),
        _isToolError(contains('direction')),
      );
      expect(
        await handleNativeScroll(context, {'direction': 'up', 'distance': 0}),
        _isToolError(contains('positive')),
      );
      expect(
        await handleNativeScroll(context, {'direction': 'up', 'startX': 5}),
        _isToolError(contains('both startX and startY')),
      );
    });

    test('swipes once without a target text', () async {
      final connector = FakeNativeConnector.single([
        nativeElement(width: 1000, height: 2000),
      ]);

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'distance': 400},
      );

      expect(result, _isToolSuccess(contains('swiped up')));
      expect(connector.swipes, [
        (startX: 500, startY: 1200, endX: 500, endY: 800),
      ]);
    });

    test('scrolls until the text appears', () async {
      final connector = FakeNativeConnector(
        screens: [
          [nativeElement(text: 'Item 1', width: 1000, height: 2000)],
          [nativeElement(text: 'Item 9', width: 1000, height: 2000)],
        ],
      );

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'text': 'Item 9'},
      );

      expect(result, _isToolSuccess(contains('after 1 swipe(s)')));
      expect(connector.swipes, hasLength(1));
    });

    test('gives up after the maximum number of swipes', () async {
      final connector = FakeNativeConnector.single([
        nativeElement(text: 'Item 1', width: 1000, height: 2000),
      ]);

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'down', 'text': 'Missing'},
      );

      expect(result, _isToolError(contains('after 10 swipe(s)')));
      expect(connector.swipes, hasLength(10));
    });
  });

  group('native_enter_text', () {
    test('requires text and exactly one target', () async {
      final context = _contextWith(FakeNativeConnector());

      expect(
        await handleNativeEnterText(context, {'id': 'field'}),
        _isToolError(contains('requires "text"')),
      );
      expect(
        await handleNativeEnterText(context, {'text': 'x'}),
        _isToolError(contains('exactly one target')),
      );
      expect(
        await handleNativeEnterText(
          context,
          {'text': 'x', 'id': 'a', 'label': 'b'},
        ),
        _isToolError(contains('exactly one target')),
      );
    });

    test('types into the field found by id or label', () async {
      final email = nativeElement(type: 'android.widget.EditText', id: 'email');
      final name = nativeElement(type: 'android.widget.EditText', text: 'Name');
      final connector = FakeNativeConnector.single([email, name]);
      final context = _contextWith(connector);

      await handleNativeEnterText(context, {'text': 'a@b.c', 'id': 'email'});
      await handleNativeEnterText(context, {'text': 'Ann', 'label': 'Name'});

      expect(connector.enteredText, [
        (element: email, text: 'a@b.c'),
        (element: name, text: 'Ann'),
      ]);
    });

    test('reports a missing field', () async {
      expect(
        await handleNativeEnterText(
          _contextWith(FakeNativeConnector()),
          {'text': 'x', 'label': 'Nope'},
        ),
        _isToolError(contains('text="Nope"')),
      );
    });
  });

  group('native_take_screenshot', () {
    test('returns the PNG as inline image content', () async {
      final result = await handleNativeTakeScreenshot(
        _contextWith(FakeNativeConnector(screenshot: 'cG5n')),
      );

      final image = result.content.whereType<ImageContent>().single;
      expect(image.data, 'cG5n');
      expect(image.mimeType, 'image/png');
    });

    test('reports an empty capture as text', () async {
      expect(
        await handleNativeTakeScreenshot(
          _contextWith(FakeNativeConnector(screenshot: '')),
        ),
        _isToolSuccess('Native screenshot was empty'),
      );
    });
  });
}
