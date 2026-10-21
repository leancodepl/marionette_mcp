import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/connection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/keyboard_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/screenshot_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/text_tools.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
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
      'native_wait_for': (c) => handleNativeWaitFor(c, {'text': 'OK'}),
      'native_swipe': (c) => handleNativeSwipe(
            c,
            {'startX': 1, 'startY': 1, 'endX': 2, 'endY': 2},
          ),
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

    test('leaves out off-screen (zero-size) elements', () async {
      final context = _contextWith(
        FakeNativeConnector.single([
          nativeElement(text: 'Visible'),
          nativeElement(text: 'Off screen', width: 0, height: 0),
        ]),
      );

      final payload = jsonDecode(_text(await handleNativeGetElements(context)))
          as Map<String, dynamic>;

      expect(
        (payload['elements'] as List).map((e) => (e as Map)['text']),
        ['Visible'],
      );
    });

    test('lists a toast although it has no bounds (D19)', () async {
      final context = _contextWith(
        FakeNativeConnector.single([
          nativeElement(text: 'Visible'),
          nativeElement(
            type: 'android.widget.Toast',
            text: 'Saved',
            clickable: false,
            width: 0,
            height: 0,
          ),
        ]),
      );

      final payload = jsonDecode(_text(await handleNativeGetElements(context)))
          as Map<String, dynamic>;

      expect(
        (payload['elements'] as List).map((e) => (e as Map)['text']),
        ['Visible', 'Saved'],
      );
    });

    test('includes element state and filters elements', () async {
      final context = _contextWith(
        FakeNativeConnector.single([
          nativeElement(text: 'Wi-Fi', type: 'Switch', checked: true),
          nativeElement(
            text: 'Name',
            type: 'android.widget.EditText',
            value: 'Zażółć',
            enabled: false,
          ),
          nativeElement(text: 'Title', clickable: false),
        ]),
      );

      final result = await handleNativeGetElements(context, {
        'textContains': 'a',
        'clickableOnly': true,
        'includeForegroundApp': false,
      });
      final payload = jsonDecode(_text(result)) as Map<String, dynamic>;

      expect(payload.containsKey('foregroundApp'), isFalse);
      final elements = payload['elements'] as List<dynamic>;
      expect(elements, hasLength(1));
      expect(elements.single, {
        'type': 'android.widget.EditText',
        'text': 'Name',
        'value': 'Zażółć',
        'bounds': {'x': 0, 'y': 0, 'width': 100, 'height': 50},
        'clickable': true,
        'enabled': false,
      });
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
    test('requires either a selector or coordinates', () async {
      final context = _contextWith(FakeNativeConnector());

      for (final args in <Map<String, dynamic>>[
        {},
        {'index': 0},
        {'text': 'OK', 'x': 1, 'y': 2},
      ]) {
        expect(
          await handleNativeTap(context, args),
          _isToolError(contains('either a selector')),
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

    test('refuses a disabled element instead of touching it', () async {
      // Seen on iOS 26.4: an app button under the document picker is
      // disabled; a tap at its position picked a file in the picker.
      final connector = FakeNativeConnector.single([
        nativeElement(text: 'Pick file', clickable: false, enabled: false),
      ]);
      final context = _contextWith(connector);

      expect(
        await handleNativeTap(context, {'text': 'Pick file'}),
        _isToolError(allOf(contains('is disabled'), contains('Hint:'))),
      );
      expect(connector.tappedElements, isEmpty);
      expect(connector.taps, isEmpty);
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

    test('taps the element chosen by the selector', () async {
      final allow = nativeElement(text: 'Allow', id: 'allow');
      final deny = nativeElement(text: 'Deny', id: 'deny');
      final connector = FakeNativeConnector.single([allow, deny]);
      final context = _contextWith(connector);

      await handleNativeTap(context, {'text': 'Deny'});
      await handleNativeTap(context, {'id': 'allow'});
      await handleNativeTap(context, {'textContains': 'den', 'type': 'Button'});

      expect(connector.tappedElements, [deny, allow, deny]);
    });

    test('an ambiguous selector fails and taps nothing (D1)', () async {
      final connector = FakeNativeConnector.single([
        nativeElement(text: 'Request', y: 100),
        nativeElement(text: 'Request', y: 200),
      ]);

      final result =
          await handleNativeTap(_contextWith(connector), {'text': 'Request'});

      expect(
        result,
        _isToolError(allOf(contains('2 native elements'), contains('index'))),
      );
      expect(connector.tappedElements, isEmpty);
    });

    test('index resolves an ambiguous selector', () async {
      final second = nativeElement(text: 'Request', y: 200);
      final connector = FakeNativeConnector.single([
        nativeElement(text: 'Request', y: 100),
        second,
      ]);

      await handleNativeTap(
        _contextWith(connector),
        {'text': 'Request', 'index': 1},
      );

      expect(connector.tappedElements, [second]);
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

    test('reports the explicit start point, not screen center', () async {
      final connector = FakeNativeConnector.single([
        nativeElement(width: 1000, height: 2000),
      ]);

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'right', 'startX': 1, 'startY': 1400},
      );

      expect(
        result,
        _isToolSuccess(
          allOf(contains('from (1, 1400)'), isNot(contains('center'))),
        ),
      );
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

    test('scrolls until an element matching the selector appears', () async {
      final connector = FakeNativeConnector(
        screens: [
          [nativeElement(text: 'Item 1')],
          [nativeElement(text: 'Item 1'), nativeElement(id: 'footer')],
        ],
      );

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'id': 'footer'},
      );

      expect(result, _isToolSuccess(contains('id="footer"')));
    });

    test('uses the real screen size, not element bounds', () async {
      final connector = FakeNativeConnector(
        screen: const NativeScreen(width: 1206, height: 2622, scale: 3),
      );

      await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'down', 'distance': 600},
      );

      expect(connector.swipes, [
        (startX: 603, startY: 1011, endX: 603, endY: 1611),
      ]);
    });

    test('gives up after the maximum number of swipes', () async {
      final connector = FakeNativeConnector(
        screens: [
          for (var i = 0; i <= 12; i++) [nativeElement(text: 'Item $i')],
        ],
      );

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'down', 'text': 'Missing'},
      );

      expect(result, _isToolError(contains('after 10 swipe(s)')));
      expect(connector.swipes, hasLength(10));
    });

    test('a zero-size (off-screen) match does not count as found', () async {
      final connector = FakeNativeConnector(
        screens: [
          [
            nativeElement(text: 'Item 1'),
            nativeElement(text: 'Target', width: 0, height: 0),
          ],
          [nativeElement(text: 'Target', y: 500)],
        ],
      );

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'text': 'Target'},
      );

      expect(result, _isToolSuccess(contains('after 1 swipe(s)')));
    });

    test('waits for the content to settle after a swipe', () async {
      // Reads 1-3 happen after the swipe while the list is still flinging.
      final connector = FakeNativeConnector()
        ..onGetElements = (call) => [
              if (call > 0)
                nativeElement(
                  text: 'Target',
                  y: switch (call) { 1 => 900, 2 => 700, _ => 650 },
                ),
            ];

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'text': 'Target'},
      );

      expect(result, _isToolSuccess(contains('after 1 swipe(s)')));
      expect(connector.getElementsCalls, 5);
      expect(connector.swipeHolds, [300], reason: 'no fling while searching');
    });

    test('maxSwipes limits the search', () async {
      final connector = FakeNativeConnector(
        screens: [
          for (var i = 0; i <= 5; i++) [nativeElement(text: 'Item $i')],
        ],
      );

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'text': 'Missing', 'maxSwipes': 3},
      );

      expect(result, _isToolError(contains('after 3 swipe(s)')));
      expect(connector.swipes, hasLength(3));
    });

    test('stops at the end of the content', () async {
      final connector = FakeNativeConnector(
        screens: [
          [nativeElement(text: 'Item 1')],
          [nativeElement(text: 'Item 2')],
        ],
      );

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'text': 'Missing'},
      );

      expect(result, _isToolError(contains('reached the end')));
      // One swipe that moves, then two without a visible change.
      expect(connector.swipes, hasLength(3));
    });

    test('one unchanged swipe (a uniform area) does not end the search',
        () async {
      // Screen 1 and 2 look the same (a blank block fills the viewport),
      // screen 3 shows the target.
      final blank = nativeElement(text: 'spacer');
      final connector = FakeNativeConnector(
        screens: [
          [blank],
          [blank],
          [nativeElement(text: 'Target')],
        ],
      );

      final result = await handleNativeScroll(
        _contextWith(connector),
        {'direction': 'up', 'text': 'Target'},
      );

      expect(result, _isToolSuccess(contains('after 2 swipe(s)')));
    });

    test('swipes inside the within container', () async {
      final connector = FakeNativeConnector.single([
        nativeElement(
          type: 'android.view.View',
          id: 'chips',
          clickable: false,
          scrollable: true,
          y: 1000,
          width: 1000,
          height: 100,
        ),
      ]);

      final context = _contextWith(connector);
      final result = await handleNativeScroll(context, {
        'direction': 'left',
        'within': {'id': 'chips'},
      });
      await handleNativeScroll(context, {
        'direction': 'left',
        'within': {'id': 'chips'},
        'distance': 200,
      });

      expect(result, _isToolSuccess(contains('within id="chips"')));
      // Centered on the container, 80% of its width unless distance is set.
      expect(connector.swipes, [
        (startX: 900, startY: 1050, endX: 100, endY: 1050),
        (startX: 600, startY: 1050, endX: 400, endY: 1050),
      ]);
    });

    test('compares only the container content for the end', () async {
      var clock = 0;
      final connector = FakeNativeConnector()
        ..onGetElements = (_) => [
              nativeElement(
                type: 'android.view.View',
                id: 'list',
                clickable: false,
                height: 500,
                width: 1000,
              ),
              nativeElement(text: 'Row 1', y: 100),
              // Outside the container; changes on every read.
              nativeElement(text: '12:0${clock++}', y: 1500),
            ];

      final result = await handleNativeScroll(_contextWith(connector), {
        'direction': 'up',
        'text': 'Row 99',
        'within': {'id': 'list'},
      });

      expect(result, _isToolError(contains('reached the end')));
      // A search swipe covers 60% of the container, as a slow held drag.
      expect(connector.swipes, [
        for (var i = 0; i < 2; i++)
          (startX: 500, startY: 400, endX: 500, endY: 100),
      ]);
      expect(connector.swipeHolds, [300, 300]);
    });

    test('validates within and maxSwipes', () async {
      final context = _contextWith(FakeNativeConnector());

      expect(
        await handleNativeScroll(context, {'direction': 'up', 'within': 'x'}),
        _isToolError(contains('selector object')),
      );
      expect(
        await handleNativeScroll(context, {
          'direction': 'up',
          'within': <String, dynamic>{},
        }),
        _isToolError(contains('at least one of')),
      );
      expect(
        await handleNativeScroll(context, {
          'direction': 'up',
          'within': {'id': 'list'},
          'startX': 1,
          'startY': 1,
        }),
        _isToolError(contains('not both')),
      );
      expect(
        await handleNativeScroll(context, {'direction': 'up', 'maxSwipes': 0}),
        _isToolError(contains('maxSwipes')),
      );
    });
  });

  group('native_enter_text', () {
    test('requires text; index requires a selector', () async {
      final context = _contextWith(FakeNativeConnector());

      expect(
        await handleNativeEnterText(context, {'id': 'field'}),
        _isToolError(contains('requires "text"')),
      );
      expect(
        await handleNativeEnterText(context, {'text': 'x', 'index': 0}),
        _isToolError(contains('index requires a selector')),
      );
    });

    test('without a selector types into the focused field', () async {
      final connector = FakeNativeConnector();

      final result = await handleNativeEnterText(
        _contextWith(connector),
        {'text': '42', 'clear': true},
      );

      expect(result, _isToolSuccess(contains('the focused field')));
      expect(connector.typedText, [(text: '42', clear: true)]);
      expect(connector.enteredText, isEmpty);
    });

    test('refuses a disabled field', () async {
      final connector = FakeNativeConnector.single([
        nativeElement(
          type: 'android.widget.EditText',
          text: 'Title',
          enabled: false,
        ),
      ]);

      expect(
        await handleNativeEnterText(
          _contextWith(connector),
          {'label': 'Title', 'text': 'x'},
        ),
        _isToolError(contains('is disabled')),
      );
      expect(connector.enteredText, isEmpty);
    });

    group('a field that changed before typing (D14)', () {
      final field = nativeElement(type: 'android.widget.EditText', id: 'f');
      for (final (name, error) in [
        (
          'iOS: no longer in the view',
          const WebDriverException(
            'The previously found element "Title" is not present in the '
            'current view anymore.',
          ),
        ),
        (
          'stale element reference',
          const WebDriverException('gone', error: 'stale element reference'),
        ),
        (
          'Android: invalid element state',
          const WebDriverException(
            "Cannot set the element to 'x'",
            error: 'invalid element state',
          ),
        ),
      ]) {
        test('is found again and typed into once ($name)', () async {
          final connector = FakeNativeConnector.single([field])
            ..enterTextErrors.add(error);

          final result = await handleNativeEnterText(
            _contextWith(connector),
            {'id': 'f', 'text': 'x'},
          );

          expect(result, _isToolSuccess(contains('Successfully entered')));
          expect(connector.enteredText.single.text, 'x');
          expect(connector.getElementsCalls, 2, reason: 'looked up again');
        });
      }

      test('changing again fails with a hint, nothing typed', () async {
        const changed =
            WebDriverException('gone', error: 'stale element reference');
        final connector = FakeNativeConnector.single([field])
          ..enterTextErrors.addAll([changed, changed]);

        final result = await handleNativeEnterText(
          _contextWith(connector),
          {'id': 'f', 'text': 'x'},
        );

        expect(result, _isToolError(contains('kept changing')));
        expect(connector.enteredText, isEmpty);
      });

      test('other WebDriver errors are not retried', () async {
        final connector = FakeNativeConnector.single([field])
          ..enterTextErrors.add(const WebDriverException('boom'));

        final result = await handleNativeEnterText(
          _contextWith(connector),
          {'id': 'f', 'text': 'x'},
        );

        expect(result.isError, isTrue);
        expect(connector.getElementsCalls, 1);
      });
    });

    test('passes clear to the selected field', () async {
      final field = nativeElement(type: 'android.widget.EditText', id: 'f');
      final connector = FakeNativeConnector.single([field]);

      await handleNativeEnterText(
        _contextWith(connector),
        {'text': 'x', 'id': 'f', 'clear': true},
      );

      expect(connector.enteredText, [(element: field, text: 'x', clear: true)]);
    });

    test('types into the field chosen by the selector', () async {
      final email = nativeElement(type: 'android.widget.EditText', id: 'email');
      final name = nativeElement(type: 'android.widget.EditText', text: 'Name');
      final connector = FakeNativeConnector.single([email, name]);
      final context = _contextWith(connector);

      await handleNativeEnterText(context, {'text': 'a@b.c', 'id': 'email'});
      await handleNativeEnterText(context, {'text': 'Ann', 'label': 'Name'});
      await handleNativeEnterText(
        context,
        {'text': 'Bo', 'type': 'EditText', 'index': 1},
      );

      expect(connector.enteredText, [
        (element: email, text: 'a@b.c', clear: false),
        (element: name, text: 'Ann', clear: false),
        (element: name, text: 'Bo', clear: false),
      ]);
    });

    test('an ambiguous field selector fails and types nothing', () async {
      final connector = FakeNativeConnector.single([
        nativeElement(type: 'android.widget.EditText'),
        nativeElement(type: 'android.widget.EditText'),
      ]);

      expect(
        await handleNativeEnterText(
          _contextWith(connector),
          {'text': 'x', 'type': 'EditText'},
        ),
        _isToolError(contains('2 native elements')),
      );
      expect(connector.enteredText, isEmpty);
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

  group('native_press_key', () {
    test('parses key names and presses the key', () async {
      final connector = FakeNativeConnector();
      final context = _contextWith(connector);

      expect(
        await handleNativePressKey(context, {'key': ' Volume_Up '}),
        _isToolSuccess('Pressed volume_up'),
      );
      await handleNativePressKey(context, {'key': 'backspace'});

      expect(connector.pressedKeys, [NativeKey.volumeUp, NativeKey.backspace]);
    });

    test('rejects unknown keys and lists the valid ones', () async {
      expect(
        await handleNativePressKey(
          _contextWith(FakeNativeConnector()),
          {'key': 'escape'},
        ),
        _isToolError(allOf(contains('back, home, enter'), contains('volume'))),
      );
    });

    test('reports an unsupported key with its hint', () async {
      final connector = FakeNativeConnector()
        ..error = const NativeUnsupportedException(
          'iOS has no Back key.',
          hint: 'Tap the navigation bar back button.',
        );

      expect(
        await handleNativePressKey(_contextWith(connector), {'key': 'back'}),
        _isToolError(allOf(contains('no Back key'), contains('Hint:'))),
      );
    });
  });

  group('native_hide_keyboard', () {
    test('reports whether the keyboard was shown', () async {
      final connector = FakeNativeConnector()..keyboardShown = true;
      final context = _contextWith(connector);

      expect(
        await handleNativeHideKeyboard(context),
        _isToolSuccess('Keyboard hidden'),
      );
      expect(
        await handleNativeHideKeyboard(context),
        _isToolSuccess('Keyboard was not shown'),
      );
    });
  });

  group('native_wait_for', () {
    test('validates the selector, state, timeout and interval', () async {
      final context = _contextWith(FakeNativeConnector());

      expect(
        await handleNativeWaitFor(context, {}),
        _isToolError(contains('requires a selector')),
      );
      expect(
        await handleNativeWaitFor(context, {'text': 'OK', 'state': 'shown'}),
        _isToolError(contains('"visible" or "gone"')),
      );
      expect(
        await handleNativeWaitFor(context, {'text': 'OK', 'timeoutMs': 60001}),
        _isToolError(contains('timeoutMs')),
      );
      expect(
        await handleNativeWaitFor(context, {'text': 'OK', 'intervalMs': 10}),
        _isToolError(contains('intervalMs')),
      );
    });

    test('keeps waiting through a failed read of an app that is starting',
        () async {
      // Seen on iOS: right after native_app activate of a terminated app,
      // the first read failed and ended the wait at once.
      final connector = FakeNativeConnector()
        ..errorsOnce.add(
          const WebDriverException('Application is not running'),
        )
        ..onGetElements = (_) => [nativeElement(text: 'Home')];

      final result = await handleNativeWaitFor(_contextWith(connector), {
        'text': 'Home',
        'intervalMs': 50,
      });

      expect(result, _isToolSuccess(contains('"state":"visible"')));
    });

    test('a read failure that lasts ends the wait after a few retries',
        () async {
      final connector = FakeNativeConnector()
        ..error = const WebDriverException('server error');
      final stopwatch = Stopwatch()..start();

      final result = await handleNativeWaitFor(_contextWith(connector), {
        'text': 'Home',
        'intervalMs': 50,
        'timeoutMs': 10000,
      });

      expect(result, _isToolError(contains('server error')));
      expect(stopwatch.elapsedMilliseconds, lessThan(2000),
          reason: 'not the whole timeoutMs');
    });

    test('returns the element once it appears', () async {
      final connector = FakeNativeConnector()
        ..onGetElements =
            (call) => call < 2 ? [] : [nativeElement(text: 'Delayed message')];

      final result = await handleNativeWaitFor(_contextWith(connector), {
        'textContains': 'delayed',
        'intervalMs': 50,
      });

      expect(result, _isToolSuccess(contains('"text":"Delayed message"')));
      expect(connector.getElementsCalls, 3);
    });

    test('ignores zero-size (off-screen) matches', () async {
      final connector = FakeNativeConnector()
        ..onGetElements = (call) => [
              nativeElement(text: 'Banner', width: call < 1 ? 0 : 100),
            ];

      final visible = await handleNativeWaitFor(
        _contextWith(connector),
        {'text': 'Banner', 'intervalMs': 50},
      );

      expect(visible, _isToolSuccess(contains('"state":"visible"')));
      expect(connector.getElementsCalls, 2);
    });

    test('finds a toast and waits until it is gone (D19)', () async {
      final connector = FakeNativeConnector()
        ..onGetElements = (call) => [
              if (call < 1)
                nativeElement(
                  type: 'android.widget.Toast',
                  text: 'Saved',
                  clickable: false,
                  width: 0,
                  height: 0,
                ),
            ];
      final context = _contextWith(connector);

      expect(
        await handleNativeWaitFor(context, {'text': 'Saved'}),
        _isToolSuccess(contains('"state":"visible"')),
      );
      expect(
        await handleNativeWaitFor(
          context,
          {'text': 'Saved', 'state': 'gone', 'intervalMs': 50},
        ),
        _isToolSuccess(contains('"state":"gone"')),
      );
    });

    test('waits until the element is gone', () async {
      final connector = FakeNativeConnector()
        ..onGetElements =
            (call) => call < 1 ? [nativeElement(text: 'Loading')] : [];

      final result = await handleNativeWaitFor(_contextWith(connector), {
        'text': 'Loading',
        'state': 'gone',
        'intervalMs': 50,
      });

      expect(result, _isToolSuccess(contains('"state":"gone"')));
    });

    test('a read slower than the timeout does not stretch the wait', () async {
      final connector = _SlowConnector(const Duration(seconds: 2));

      final stopwatch = Stopwatch()..start();
      final result = await handleNativeWaitFor(
        _contextWith(connector),
        {'text': 'X', 'timeoutMs': 200},
      );

      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(result, _isToolError(contains('did not finish within 200ms')));
    });

    test('times out with a hint', () async {
      final connector = FakeNativeConnector.single([nativeElement(text: 'A')]);

      final visible = await handleNativeWaitFor(_contextWith(connector), {
        'text': 'B',
        'timeoutMs': 120,
        'intervalMs': 50,
      });
      final gone = await handleNativeWaitFor(_contextWith(connector), {
        'text': 'A',
        'state': 'gone',
        'timeoutMs': 120,
        'intervalMs': 50,
      });

      expect(
        visible,
        _isToolError(contains('within 120ms in com.example.app')),
      );
      expect(gone, _isToolError(contains('still visible after 120ms')));
    });
  });

  group('native_swipe', () {
    test('swipes between the given points', () async {
      final connector = FakeNativeConnector();

      final result = await handleNativeSwipe(_contextWith(connector), {
        'startX': 1,
        'startY': 1000,
        'endX': 800,
        'endY': 1000,
      });

      expect(result, _isToolSuccess(contains('(800, 1000)')));
      expect(
        connector.swipes.single,
        (startX: 1, startY: 1000, endX: 800, endY: 1000),
      );
    });

    test('requires all four coordinates', () async {
      expect(
        await handleNativeSwipe(
          _contextWith(FakeNativeConnector()),
          {'startX': 1, 'startY': 1, 'endX': 2},
        ),
        _isToolError(contains('requires startX, startY, endX and endY')),
      );
    });
  });
}

/// A connector whose UI-tree reads take [delay].
class _SlowConnector extends FakeNativeConnector {
  _SlowConnector(this.delay);

  final Duration delay;

  @override
  Future<List<NativeElement>> getNativeElements() async {
    await Future<void>.delayed(delay);
    return const [];
  }
}
