import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:test/test.dart';

import 'support/fake_native_connector.dart';
import 'support/fake_process_runner.dart';
import 'support/fake_webdriver_server.dart';

const _noSuchElement = FakeResponse.error(
  'no such element',
  'not found',
  status: HttpStatus.notFound,
);

/// Extracts the pointer coordinates of a single-finger tap/swipe request.
({int x, int y}) _pointerStart(RecordedRequest request) {
  final source = (request.body!['actions'] as List).single as Map;
  final move = (source['actions'] as List).first as Map;
  return (x: move['x'] as int, y: move['y'] as int);
}

/// Pointer action lists of a W3C actions request, one per finger.
List<List<Map<String, dynamic>>> _fingers(RecordedRequest request) => [
      for (final source in request.body!['actions'] as List)
        [
          for (final action in (source as Map)['actions'] as List)
            action as Map<String, dynamic>,
        ],
    ];

/// `dumpsys window windows` excerpt for Gboard's floating toolbar on API 35.
const _floatingImeDumpsys = '''
  Window #7 Window{ad0968f u0 InputMethod}:
    mAttrs={(0,0)(fillxfill) gr=BOTTOM CENTER_VERTICAL ty=INPUT_METHOD}
    Requested w=1280 h=2700 mLayoutSeq=577
    mGivenContentInsets=[0,2700][0,0] mGivenVisibleInsets=[0,2700][0,0]
  Window #8 Window{1b2c u0 com.example.counter/com.example.counter.MainActivity}:
    Requested w=1280 h=2856 mLayoutSeq=577
    mGivenContentInsets=[0,0][0,0]
''';

void main() {
  late FakeWebDriverServer server;
  late FakeServerBootstrap bootstrap;

  setUp(() async {
    server = await FakeWebDriverServer.start();
    bootstrap = FakeServerBootstrap(server.baseUrl);
  });

  tearDown(() => server.close());

  group('AndroidNativeConnector', () {
    late FakeProcessRunner runner;

    setUp(() => runner = FakeProcessRunner());

    Future<AndroidNativeConnector> connect() => AndroidNativeConnector.connect(
          bootstrap: bootstrap,
          adb: AdbClient(serial: 'emulator-5554', processRunner: runner.call),
        );

    test('creates a UiAutomator2 session on the bootstrapped server', () async {
      final connector = await connect();
      addTearDown(connector.dispose);

      expect(bootstrap.ensureCalls, 1);
      expect(
        server.requestsTo('POST', '/session').single.body,
        {
          'capabilities': {
            'alwaysMatch': {
              'platformName': 'Android',
              'appium:automationName': 'UiAutomator2',
            },
          },
        },
      );
    });

    test('lowers the UIAutomator2 idle wait for the session (D18)', () async {
      server.onValue('POST', '/session/sess-1/appium/settings', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      expect(
        server
            .requestsTo('POST', '/session/sess-1/appium/settings')
            .single
            .body,
        {
          'settings': {'waitForIdleTimeout': 500},
        },
      );
    });

    test(
        'a session on a server another process started is not deleted '
        '(D10)', () async {
      final shared = _SharedBootstrap(server.baseUrl, startedServer: false);
      final connector = await AndroidNativeConnector.connect(
        bootstrap: shared,
        adb: AdbClient(serial: 'emulator-5554', processRunner: runner.call),
      );

      await connector.dispose();

      expect(server.requestsTo('DELETE', '/session/sess-1'), isEmpty);
    });

    test('a session on a server this bootstrap started is deleted', () async {
      final own = _SharedBootstrap(server.baseUrl, startedServer: true);
      final connector = await AndroidNativeConnector.connect(
        bootstrap: own,
        adb: AdbClient(serial: 'emulator-5554', processRunner: runner.call),
      );

      await connector.dispose();

      expect(server.requestsTo('DELETE', '/session/sess-1'), hasLength(1));
    });

    test('reopenSession: a new session on the same server takes it over (D3)',
        () async {
      final owned = _SharedBootstrap(server.baseUrl, startedServer: true);
      final first = await AndroidNativeConnector.connect(
        bootstrap: owned,
        adb: AdbClient(serial: 'emulator-5554', processRunner: runner.call),
        ownsBootstrap: true,
      );

      final second = await first.reopenSession();
      await first.dispose();

      expect(second, isNotNull);
      expect(server.requestsTo('POST', '/session'), hasLength(2));
      expect(owned.disposeCalls, 0, reason: 'the server moved to the new one');
      await second!.dispose();
      expect(owned.disposeCalls, 1);
    });

    group('reusing a session (D4)', () {
      Future<AndroidNativeConnector> connectTo(String sessionId) =>
          AndroidNativeConnector.connect(
            bootstrap: bootstrap,
            adb: AdbClient(serial: 'emulator-5554', processRunner: runner.call),
            sessionId: sessionId,
          );

      test('a live session is reused without a new session or settings',
          () async {
        server.onValue('GET', '/session/kept/orientation', 'PORTRAIT');

        final connector = await connectTo('kept');
        connector.release();

        expect(connector.sessionId, 'kept');
        expect(server.requestsTo('POST', '/session'), isEmpty);
        expect(
          server.requestsTo('POST', '/session/kept/appium/settings'),
          isEmpty,
        );
        expect(server.requestsTo('DELETE', '/session/kept'), isEmpty,
            reason: 'release keeps the session');
      });

      test('a session the server no longer has is replaced', () async {
        final connector = await connectTo('gone');
        addTearDown(connector.dispose);

        expect(connector.sessionId, 'sess-1');
        expect(server.requestsTo('POST', '/session'), hasLength(1));
        expect(
          server.requestsTo('POST', '/session/sess-1/appium/settings'),
          hasLength(1),
        );
      });
    });

    group('while a toast is shown (D19)', () {
      const toastError = FakeResponse.error(
        'unknown error',
        "Cannot set AccessibilityNodeInfo's field 'mSealed' to 'true'",
        status: HttpStatus.internalServerError,
      );

      test('tree reads are retried until the toast is gone', () async {
        var calls = 0;
        server.on('GET', '/session/sess-1/source', (_) {
          calls++;
          return calls <= 2
              ? toastError
              : const FakeResponse.value(
                  '<hierarchy><node class="android.widget.Button" '
                  'text="OK" clickable="true" bounds="[0,0][10,10]"/>'
                  '</hierarchy>',
                );
        });
        final connector = await connect();
        addTearDown(connector.dispose);

        final elements = await connector.getNativeElements();

        expect(elements.single.text, 'OK');
        expect(calls, 3);
      });

      test('a toast that never goes away becomes a typed error', () async {
        server.on('GET', '/session/sess-1/source', (_) => toastError);
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.getNativeElements(),
          throwsA(
            isA<NativeOperationFailedException>()
                .having((e) => e.hint, 'hint', contains('toast')),
          ),
        );
      }, timeout: const Timeout(Duration(seconds: 20)));

      test('other server errors are not retried', () async {
        var calls = 0;
        server.on('GET', '/session/sess-1/source', (_) {
          calls++;
          return const FakeResponse.error(
            'unknown error',
            'Something else went wrong',
            status: HttpStatus.internalServerError,
          );
        });
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.getNativeElements(),
          throwsA(isNot(isA<NativeOperationFailedException>())),
        );
        expect(calls, 1);
      });
    });

    test('getNativeElements parses the page source', () async {
      server.onValue(
        'GET',
        '/session/sess-1/source',
        '<hierarchy><node class="android.widget.Button" text="Allow" '
            'clickable="true" bounds="[0,0][100,50]"/></hierarchy>',
      );
      final connector = await connect();
      addTearDown(connector.dispose);

      final elements = await connector.getNativeElements();

      expect(elements.single.text, 'Allow');
      expect(elements.single.center, (x: 50, y: 25));
    });

    test('tapElement taps the element center', () async {
      server.onValue('POST', '/session/sess-1/actions', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.tapElement(nativeElement(x: 100, y: 200));

      expect(
        _pointerStart(
            server.requestsTo('POST', '/session/sess-1/actions').single),
        (x: 150, y: 225),
      );
    });

    test('enterText falls back to an XPath-safe label lookup', () async {
      server
        ..onValue('POST', '/session/sess-1/actions', null)
        ..on('POST', '/session/sess-1/element', (request) {
          final selector = request.body!['value'] as String;
          return selector.contains('focused')
              ? _noSuchElement
              : const FakeResponse.value({w3cElementKey: 'el-1'});
        })
        ..onValue('POST', '/session/sess-1/element/el-1/value', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.enterText(nativeElement(text: "Owner's name"), 'Ann');

      final lookups = server
          .requestsTo('POST', '/session/sess-1/element')
          .map((r) => r.body!['value'] as String)
          .toList();
      expect(lookups.last, contains('@text="Owner\'s name"'));
      expect(
        server
            .requestsTo('POST', '/session/sess-1/element/el-1/value')
            .single
            .body,
        {'text': 'Ann'},
      );
    });

    test('foregroundApp asks adb for the focused package', () async {
      runner.onAdb(
        ['shell', 'dumpsys', 'window', 'displays'],
        result: ok('mCurrentFocus=Window{1 u0 com.example.app/.MainActivity}'),
      );
      final connector = await connect();
      addTearDown(connector.dispose);

      expect(await connector.foregroundApp, 'com.example.app');
      expect(runner.calls.single.arguments.take(2), ['-s', 'emulator-5554']);
    });

    test('dispose is idempotent and keeps an injected bootstrap', () async {
      final connector = await connect();

      await connector.dispose();
      await connector.dispose();

      expect(server.requestsTo('DELETE', '/session/sess-1'), hasLength(1));
      expect(bootstrap.disposeCalls, 0);
    });

    test('getScreen reads UIAutomator2 window size in pixels', () async {
      server.onValue(
        'GET',
        '/session/sess-1/window/current/size',
        {'width': 1080, 'height': 2160},
      );
      final connector = await connect();
      addTearDown(connector.dispose);

      expect((await connector.getScreen()).toJson(), {
        'width': 1080,
        'height': 2160,
        'scale': 1.0,
      });
    });

    test('getScreen falls back to adb wm size', () async {
      runner.onAdb(
        ['shell', 'wm', 'size'],
        result: ok('Physical size: 1280x2856\n'),
      );
      final connector = await connect();
      addTearDown(connector.dispose);

      expect((await connector.getScreen()).width, 1280);
    });

    group('keyboard', () {
      setUp(() {
        server.onValue(
          'POST',
          '/session/sess-1/appium/device/press_keycode',
          null,
        );
      });

      List<int> keycodes() => server
          .requestsTo('POST', '/session/sess-1/appium/device/press_keycode')
          .map((r) => r.body!['keycode'] as int)
          .toList();

      void keyboardShown(List<bool> states) {
        var call = 0;
        runner.onAdb(
          ['shell', 'dumpsys', 'input_method'],
          respond: (_) => ok(
            'mInputShown=${states[call < states.length ? call++ : states.length - 1]}',
          ),
        );
      }

      test('pressKey sends Android keycodes', () async {
        final connector = await connect();
        addTearDown(connector.dispose);

        for (final key in NativeKey.values) {
          await connector.pressKey(key);
        }

        expect(keycodes(), [4, 3, 66, 67, 61, 187, 24, 25]);
      });

      test('hideKeyboard does not press Back when no keyboard is shown',
          () async {
        keyboardShown([false]);
        final connector = await connect();
        addTearDown(connector.dispose);

        expect(await connector.hideKeyboard(), isFalse);
        expect(keycodes(), isEmpty, reason: 'Back would navigate away');
      });

      test('hideKeyboard presses Back once and waits for the IME to close',
          () async {
        keyboardShown([true, true, false]);
        final connector = await connect();
        addTearDown(connector.dispose);

        expect(await connector.hideKeyboard(), isTrue);
        expect(keycodes(), [4]);
      });

      test('hideKeyboard never presses Back for the floating toolbar',
          () async {
        // Gboard with a hardware keyboard attached: the IME window covers
        // nothing, Back would go to the app (seen on API 35).
        keyboardShown([true]);
        runner.onAdb(
          ['shell', 'dumpsys', 'window', 'windows'],
          result: ok(_floatingImeDumpsys),
        );
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.hideKeyboard(),
          throwsA(
            isA<NativeOperationFailedException>()
                .having((e) => e.message, 'message', contains('floating')),
          ),
        );
        expect(keycodes(), isEmpty);
      });

      test('hideKeyboard fails when the IME stays open', () async {
        keyboardShown([true]);
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.hideKeyboard(),
          throwsA(isA<NativeOperationFailedException>()),
        );
      });

      test('typeText types into the active element, clearing on request',
          () async {
        server
          ..onValue('GET', '/session/sess-1/element/active', {
            w3cElementKey: 'focused',
          })
          ..onValue('POST', '/session/sess-1/element/focused/clear', null)
          ..onValue('POST', '/session/sess-1/element/focused/value', null);
        final connector = await connect();
        addTearDown(connector.dispose);

        await connector.typeText('42', clear: true);

        expect(
          server.requestsTo('POST', '/session/sess-1/element/focused/clear'),
          hasLength(1),
        );
        expect(
          server
              .requestsTo('POST', '/session/sess-1/element/focused/value')
              .single
              .body,
          {'text': '42'},
        );
      });

      test('typeText refuses when focus is on something other than a field',
          () async {
        // After a Tab press focus can sit on a button; UIAutomator2 would
        // accept send keys there without typing anything.
        server
          ..onValue('GET', '/session/sess-1/element/active', {
            w3cElementKey: 'btn',
          })
          ..onValue(
            'GET',
            '/session/sess-1/element/btn/attribute/className',
            'android.widget.Button',
          );
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.typeText('x'),
          throwsA(
            isA<NativeElementNotFoundException>().having(
              (e) => e.message,
              'message',
              contains('focus is on android.widget.Button'),
            ),
          ),
        );
        expect(
          server.requestsTo('POST', '/session/sess-1/element/btn/value'),
          isEmpty,
        );
      });

      test('typeText accepts EditText subclasses', () async {
        server
          ..onValue('GET', '/session/sess-1/element/active', {
            w3cElementKey: 'f',
          })
          ..onValue(
            'GET',
            '/session/sess-1/element/f/attribute/className',
            'com.google.android.material.textfield.TextInputEditText',
          )
          ..onValue('POST', '/session/sess-1/element/f/value', null);
        final connector = await connect();
        addTearDown(connector.dispose);

        await connector.typeText('ok');

        expect(
          server.requestsTo('POST', '/session/sess-1/element/f/value'),
          hasLength(1),
        );
      });

      test('typeText without a focused field asks to focus one', () async {
        server.on(
          'GET',
          '/session/sess-1/element/active',
          (_) => const FakeResponse.error(
            'no such element',
            'nothing focused',
            status: HttpStatus.notFound,
          ),
        );
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.typeText('x'),
          throwsA(
            isA<NativeElementNotFoundException>()
                .having((e) => e.hint, 'hint', contains('Focus a text field')),
          ),
        );
      });
    });

    group('gestures (N-06)', () {
      setUp(() => server.onValue('POST', '/session/sess-1/actions', null));

      test('longPress holds the finger down for the duration', () async {
        final connector = await connect();
        addTearDown(connector.dispose);

        await connector.longPress(100, 200, durationMs: 800);

        final [finger] = _fingers(
          server.requestsTo('POST', '/session/sess-1/actions').single,
        );
        expect(finger.map((a) => a['type']), [
          'pointerMove',
          'pointerDown',
          'pause',
          'pointerUp',
        ]);
        expect((finger[0]['x'], finger[0]['y']), (100, 200));
        expect(finger[2]['duration'], 800);
      });

      test('doubleTap sends both taps in one request', () async {
        final connector = await connect();
        addTearDown(connector.dispose);

        await connector.doubleTap(10, 20, delayMs: 120);

        final [finger] = _fingers(
          server.requestsTo('POST', '/session/sess-1/actions').single,
        );
        expect(finger.where((a) => a['type'] == 'pointerDown'), hasLength(2));
        expect(finger[4], {'type': 'pause', 'duration': 120});
      });

      test('pinch moves two fingers apart horizontally', () async {
        final connector = await connect();
        addTearDown(connector.dispose);

        await connector.pinch(
          centerX: 500,
          centerY: 1000,
          startSpan: 200,
          endSpan: 600,
        );

        final [left, right] = _fingers(
          server.requestsTo('POST', '/session/sess-1/actions').single,
        );
        expect((left[0]['x'], right[0]['x']), (400, 600));
        expect((left[2]['x'], right[2]['x']), (200, 800));
        expect(left[2]['y'], 1000);
      });
    });

    test('takeElementScreenshot finds the element by class and bounds',
        () async {
      server
        ..onValue('POST', '/session/sess-1/element', {w3cElementKey: 'e-1'})
        ..onValue('GET', '/session/sess-1/element/e-1/screenshot', 'png');
      final connector = await connect();
      addTearDown(connector.dispose);

      final png = await connector.takeElementScreenshot(
        nativeElement(x: 10, y: 20, width: 100, height: 50),
      );

      expect(png, 'png');
      expect(
        server
            .requestsTo('POST', '/session/sess-1/element')
            .single
            .body!['value'],
        "//*[@class='android.widget.Button' and "
        '@bounds="[10,20][110,70]"]',
      );
    });

    test('takeElementScreenshot reports an element that is gone', () async {
      server.on('POST', '/session/sess-1/element', (_) => _noSuchElement);
      final connector = await connect();
      addTearDown(connector.dispose);

      await expectLater(
        connector.takeElementScreenshot(nativeElement(id: 'logo')),
        throwsA(isA<NativeElementNotFoundException>()),
      );
      // Geometry first, then the resource id.
      expect(
          server.requestsTo('POST', '/session/sess-1/element'), hasLength(2));
    });

    test('isServerResponding reflects /status', () async {
      final connector = await connect();
      addTearDown(connector.dispose);

      expect(await connector.isServerResponding(), isTrue);

      server.on(
        'GET',
        '/status',
        (_) => const FakeResponse.raw('', status: HttpStatus.badGateway),
      );
      expect(await connector.isServerResponding(), isFalse);
    });

    test('failed session creation does not dispose an injected bootstrap',
        () async {
      server.on(
        'POST',
        '/session',
        (_) => const FakeResponse.error('session not created', 'busy'),
      );

      await expectLater(connect(), throwsA(isA<WebDriverException>()));
      expect(bootstrap.disposeCalls, 0);
    });
  });

  group('IosNativeConnector', () {
    // An iPhone-like display: 402x874 points at scale 3.
    setUp(() {
      server.onValue('GET', '/session/sess-1/wda/screen', {
        'statusBarSize': {'width': 402, 'height': 54},
        'scale': 3,
        'screenSize': {'width': 402, 'height': 874},
      });
    });

    Future<IosNativeConnector> connect() =>
        IosNativeConnector.connect(bootstrap: bootstrap);

    test('tapElement taps the chosen element even when its id repeats',
        () async {
      // Two "Request" buttons share label and id; the selector picked the
      // second one, so WDA must not be asked to find "Request" again.
      server.onValue('POST', '/session/sess-1/actions', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.tapElement(
        nativeElement(
          type: 'XCUIElementTypeButton',
          text: 'Request',
          id: 'Request',
          x: 819,
          y: 1278,
          width: 315,
          height: 144,
        ),
      );

      expect(server.requestsTo('POST', '/session/sess-1/element'), isEmpty);
      expect(
        _pointerStart(
          server.requestsTo('POST', '/session/sess-1/actions').single,
        ),
        (x: 325, y: 450),
      );
    });

    test('tapElement falls back to the element center', () async {
      server
        ..on('POST', '/session/sess-1/element', (_) => _noSuchElement)
        ..onValue('POST', '/session/sess-1/actions', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      // Bounds are screenshot pixels; the center (60, 36) is sent to WDA in
      // points.
      await connector.tapElement(
        nativeElement(text: 'OK', x: 12, y: 12, width: 96, height: 48),
      );

      expect(
        _pointerStart(
            server.requestsTo('POST', '/session/sess-1/actions').single),
        (x: 20, y: 12),
      );
    });

    test('reports element bounds in screenshot pixels', () async {
      server.onValue(
        'GET',
        '/session/sess-1/source',
        '<XCUIElementTypeApplication><XCUIElementTypeButton label="OK" '
            'enabled="true" x="10" y="20" width="100" height="44"/>'
            '</XCUIElementTypeApplication>',
      );
      final connector = await connect();
      addTearDown(connector.dispose);

      final button = (await connector.getNativeElements())
          .singleWhere((e) => e.text == 'OK');

      expect(button.bounds.toJson(), {
        'x': 30,
        'y': 60,
        'width': 300,
        'height': 132,
      });
    });

    test('swipe and tapAt convert screenshot pixels to points', () async {
      server.onValue('POST', '/session/sess-1/actions', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.tapAt(600, 1200);
      await connector.swipe(startX: 300, startY: 1500, endX: 300, endY: 300);

      final requests = server.requestsTo('POST', '/session/sess-1/actions');
      expect(_pointerStart(requests[0]), (x: 200, y: 400));
      final swipe = ((requests[1].body!['actions'] as List).single
          as Map)['actions'] as List;
      expect((swipe.first as Map)['y'], 500);
      expect((swipe[2] as Map)['y'], 100);
    });

    test('gestures convert screenshot pixels to points', () async {
      server.onValue('POST', '/session/sess-1/actions', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.longPress(300, 600);
      await connector.pinch(
        centerX: 600,
        centerY: 1200,
        startSpan: 600,
        endSpan: 300,
      );

      final [press, pinch] =
          server.requestsTo('POST', '/session/sess-1/actions');
      final [finger] = _fingers(press);
      expect((finger[0]['x'], finger[0]['y']), (100, 200));
      final [left, right] = _fingers(pinch);
      expect((left[0]['x'], right[0]['x']), (100, 300));
      expect((left[2]['x'], right[2]['x']), (150, 250));
      expect(left[0]['y'], 400);
    });

    test('takeElementScreenshot finds the element by geometry in points',
        () async {
      server
        ..onValue('POST', '/session/sess-1/element', {w3cElementKey: 'e-1'})
        ..onValue('GET', '/session/sess-1/element/e-1/screenshot', 'png');
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.takeElementScreenshot(
        nativeElement(
          type: 'XCUIElementTypeImage',
          x: 30,
          y: 60,
          width: 300,
          height: 150,
        ),
      );

      expect(
        server
            .requestsTo('POST', '/session/sess-1/element')
            .single
            .body!['value'],
        '//XCUIElementTypeImage[@x=10 and @y=20 and @width=100 and '
        '@height=50]',
      );
    });

    test('a refused rotation becomes a typed error with a hint', () async {
      server.on(
        'POST',
        '/session/sess-1/orientation',
        (_) => const FakeResponse.error(
          'unknown error',
          'Unable To Rotate Device',
          status: HttpStatus.internalServerError,
        ),
      );
      final connector = await connect();
      addTearDown(connector.dispose);

      await expectLater(
        connector.setOrientation(NativeOrientation.landscape),
        throwsA(
          isA<NativeOperationFailedException>()
              .having((e) => e.hint, 'hint', contains('native_notifications')),
        ),
      );
    });

    test('getScreen reports the screen in screenshot pixels', () async {
      final connector = await connect();
      addTearDown(connector.dispose);

      final screen = await connector.getScreen();

      expect(screen.toJson(), {'width': 1206, 'height': 2622, 'scale': 3.0});
    });

    test('derives the scale from the screenshot when wda/screen is missing',
        () async {
      server
        ..on(
          'GET',
          '/session/sess-1/wda/screen',
          (_) => const FakeResponse.error(
            'unknown command',
            'nope',
            status: HttpStatus.notFound,
          ),
        )
        ..onValue('GET', '/session/sess-1/window/rect', {
          'x': 0,
          'y': 0,
          'width': 375,
          'height': 667,
        })
        ..onValue('GET', '/session/sess-1/screenshot', _pngHeader(750, 1334));
      final connector = await connect();
      addTearDown(connector.dispose);

      expect((await connector.getScreen()).toJson(), {
        'width': 750,
        'height': 1334,
        'scale': 2.0,
      });
    });

    test('connect fails when the display scale cannot be determined', () async {
      server.on(
        'GET',
        '/session/sess-1/wda/screen',
        (_) => const FakeResponse.error('unknown command', 'nope'),
      );

      await expectLater(connect(), throwsA(isA<WebDriverException>()));
      expect(server.requestsTo('DELETE', '/session/sess-1'), hasLength(1));
    });

    test('enterText finds the field by type and geometry in points', () async {
      server
        ..onValue('POST', '/session/sess-1/element', {w3cElementKey: 'f-1'})
        ..onValue('POST', '/session/sess-1/element/f-1/click', null)
        ..onValue('POST', '/session/sess-1/element/f-1/value', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.enterText(
        nativeElement(
          type: 'XCUIElementTypeTextField',
          id: 'native_input',
          x: 96,
          y: 1764,
          width: 1014,
          height: 102,
        ),
        'hi',
      );

      expect(
        server
            .requestsTo('POST', '/session/sess-1/element')
            .single
            .body!['value'],
        '//XCUIElementTypeTextField[@x=32 and @y=588 and @width=338 and '
        '@height=34]',
      );
    });

    test('the label fallback builds a valid XPath literal for apostrophes',
        () async {
      server
        ..on('POST', '/session/sess-1/element', (request) {
          final value = request.body!['value'] as String;
          return request.body!['using'] == 'xpath' && value.contains('@label')
              ? const FakeResponse.value({w3cElementKey: 'el-1'})
              : _noSuchElement;
        })
        ..onValue('POST', '/session/sess-1/element/el-1/click', null)
        ..onValue('POST', '/session/sess-1/element/el-1/value', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.enterText(nativeElement(text: "Don't Allow"), 'x');

      final xpath = server
          .requestsTo('POST', '/session/sess-1/element')
          .last
          .body!['value'] as String;
      expect(
        xpath,
        '//*[@label="Don\'t Allow" or @name="Don\'t Allow" or '
        '@value="Don\'t Allow"]',
      );
    });

    test('enterText looks the field up once, then clicks and types', () async {
      server
        ..onValue(
          'POST',
          '/session/sess-1/element',
          {w3cElementKey: 'field-1'},
        )
        ..onValue('POST', '/session/sess-1/element/field-1/click', null)
        ..onValue('POST', '/session/sess-1/element/field-1/value', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.enterText(nativeElement(id: 'email'), 'a@b.c');

      expect(
          server.requestsTo('POST', '/session/sess-1/element'), hasLength(1));
      expect(
        server
            .requestsTo('POST', '/session/sess-1/element/field-1/value')
            .single
            .body,
        {'text': 'a@b.c'},
      );
    });

    test('enterText reports a missing field without tapping', () async {
      server.on('POST', '/session/sess-1/element', (_) => _noSuchElement);
      final connector = await connect();
      addTearDown(connector.dispose);

      await expectLater(
        connector.enterText(nativeElement(id: 'missing'), 'x'),
        throwsA(
          isA<WebDriverException>()
              .having((e) => e.error, 'error', 'no such element'),
        ),
      );
      expect(server.requestsTo('POST', '/session/sess-1/actions'), isEmpty);
    });

    test('foregroundApp falls back to the page source', () async {
      server
        ..on(
          'GET',
          '/session/sess-1/wda/activeAppInfo',
          (_) => const FakeResponse.error('unknown command', 'nope'),
        )
        ..onValue(
          'GET',
          '/session/sess-1/source',
          '<XCUIElementTypeApplication name="com.apple.springboard"/>',
        );
      final connector = await connect();
      addTearDown(connector.dispose);

      expect(await connector.foregroundApp, 'com.apple.springboard');
    });

    group('keyboard', () {
      test('pressKey maps buttons and keyboard keys', () async {
        server
          ..onValue('POST', '/session/sess-1/wda/pressButton', null)
          ..onValue('POST', '/session/sess-1/wda/keys', null);
        final connector = await connect();
        addTearDown(connector.dispose);

        await connector.pressKey(NativeKey.home);
        await connector.pressKey(NativeKey.enter);
        await connector.pressKey(NativeKey.backspace);

        expect(
          server
              .requestsTo('POST', '/session/sess-1/wda/pressButton')
              .single
              .body,
          {'name': 'home'},
        );
        expect(
          server
              .requestsTo('POST', '/session/sess-1/wda/keys')
              .map((r) => r.body!['value']),
          [
            ['\n'],
            ['\b'],
          ],
        );
      });

      test('back, recents and tab are unsupported, with a hint', () async {
        final connector = await connect();
        addTearDown(connector.dispose);

        // tab: `\t` would be typed as a character, not move focus.
        for (final key in [NativeKey.back, NativeKey.recents, NativeKey.tab]) {
          await expectLater(
            connector.pressKey(key),
            throwsA(isA<NativeUnsupportedException>()),
            reason: key.wireName,
          );
        }
      });

      test('the back hint suggests an edge swipe long enough to pop', () async {
        final connector = await connect();
        addTearDown(connector.dispose);

        // A 400 px edge swipe (native_scroll default) is cancelled by iOS.
        await expectLater(
          connector.pressKey(NativeKey.back),
          throwsA(
            isA<NativeUnsupportedException>().having(
              (e) => e.hint,
              'hint',
              allOf(contains('native_swipe startX=1'), contains('70%')),
            ),
          ),
        );
      });

      test('a button the Simulator lacks is reported as unsupported', () async {
        server.on(
          'POST',
          '/session/sess-1/wda/pressButton',
          (_) => const FakeResponse.error(
            'unknown error',
            "The button 'volumeUp' is not supported.",
          ),
        );
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.pressKey(NativeKey.volumeUp),
          throwsA(
            isA<NativeUnsupportedException>()
                .having((e) => e.hint, 'hint', contains('Simulator')),
          ),
        );
      });

      test('typeText checks the focused element type', () async {
        var type = 'XCUIElementTypeButton';
        server
          ..onValue('GET', '/session/sess-1/element/active', {
            w3cElementKey: 'el',
          })
          ..on(
            'GET',
            '/session/sess-1/element/el/attribute/type',
            (_) => FakeResponse.value(type),
          )
          ..onValue('POST', '/session/sess-1/element/el/value', null);
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.typeText('x'),
          throwsA(isA<NativeElementNotFoundException>()),
        );

        type = 'XCUIElementTypeTextView';
        await connector.typeText('x');
        expect(
          server.requestsTo('POST', '/session/sess-1/element/el/value'),
          hasLength(1),
        );
      });

      void sourceWithKeyboard(List<bool> shown) {
        var call = 0;
        server.on('GET', '/session/sess-1/source', (_) {
          final visible =
              shown[call < shown.length ? call++ : shown.length - 1];
          return FakeResponse.value(
            '<XCUIElementTypeApplication>'
            '${visible ? '<XCUIElementTypeKeyboard/>' : ''}'
            '</XCUIElementTypeApplication>',
          );
        });
      }

      test('a keyboard parked below the screen is not shown', () async {
        // Seen on iOS 18.6: dismissed while the field kept focus, the
        // keyboard stays in the tree at y = screen height.
        server.onValue(
          'GET',
          '/session/sess-1/source',
          '<XCUIElementTypeApplication x="0" y="0" width="440" height="956">'
              '<XCUIElementTypeKeyboard visible="false" x="0" y="956" '
              'width="440" height="243"/></XCUIElementTypeApplication>',
        );
        final connector = await connect();
        addTearDown(connector.dispose);

        expect(await connector.isKeyboardShown(), isFalse);
        expect(await connector.hideKeyboard(), isFalse);
        expect(
          server.requestsTo(
            'POST',
            '/session/sess-1/wda/keyboard/dismiss',
          ),
          isEmpty,
        );
      });

      test('an on-screen keyboard is shown', () {
        expect(
          wdaKeyboardOnScreen(
            '<XCUIElementTypeApplication x="0" y="0" width="440" '
            'height="956"><XCUIElementTypeKeyboard x="0" y="665" '
            'width="440" height="291"/></XCUIElementTypeApplication>',
          ),
          isTrue,
        );
        expect(
          wdaKeyboardOnScreen('<XCUIElementTypeApplication height="956"/>'),
          isFalse,
        );
      });

      test('hideKeyboard is a no-op without a keyboard', () async {
        sourceWithKeyboard([false]);
        final connector = await connect();
        addTearDown(connector.dispose);

        expect(await connector.hideKeyboard(), isFalse);
        expect(
          server.requestsTo('POST', '/session/sess-1/wda/keyboard/dismiss'),
          isEmpty,
        );
      });

      test('hideKeyboard uses only non-editing dismiss keys', () async {
        sourceWithKeyboard([true, false]);
        server.onValue('POST', '/session/sess-1/wda/keyboard/dismiss', null);
        final connector = await connect();
        addTearDown(connector.dispose);

        expect(await connector.hideKeyboard(), isTrue);
        final keyNames = server
            .requestsTo('POST', '/session/sess-1/wda/keyboard/dismiss')
            .single
            .body!['keyNames'] as List;
        expect(keyNames, contains('Done'));
        expect(
          keyNames.map((k) => (k as String).toLowerCase()),
          isNot(contains('return')),
          reason: 'return inserts a newline in multi-line fields',
        );
      });

      test('hideKeyboard fails fast when WDA cannot dismiss it', () async {
        sourceWithKeyboard([true]);
        server.on(
          'POST',
          '/session/sess-1/wda/keyboard/dismiss',
          (_) => const FakeResponse.error(
            'unknown error',
            'Did not know how to dismiss the keyboard.',
          ),
        );
        final connector = await connect();
        addTearDown(connector.dispose);

        await expectLater(
          connector.hideKeyboard(),
          throwsA(isA<NativeOperationFailedException>()),
        );
        expect(
          server.requestsTo('GET', '/session/sess-1/source'),
          hasLength(2),
          reason: 'one check before, one after — no polling',
        );
      });
    });

    test('dispose is idempotent and keeps an injected bootstrap', () async {
      final connector = await connect();

      await connector.dispose();
      await connector.dispose();

      expect(server.requestsTo('DELETE', '/session/sess-1'), hasLength(1));
      expect(bootstrap.disposeCalls, 0);
    });
  });
}

/// Base64 of a PNG signature + IHDR header for a [width]x[height] image.
String _pngHeader(int width, int height) {
  List<int> uint32(int value) =>
      [value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF];
  return base64Encode([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
    ...uint32(width),
    ...uint32(height),
    8, 6, 0, 0, 0, 0, 0, 0, 0, // rest of IHDR + CRC (unchecked)
  ]);
}

/// A bootstrap that reports whether it started the server.
class _SharedBootstrap extends FakeServerBootstrap
    implements SharedServerBootstrap {
  _SharedBootstrap(super.baseUrl, {required this.startedServer});

  @override
  final bool startedServer;
}
