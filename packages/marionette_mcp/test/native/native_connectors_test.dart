import 'dart:io';

import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
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
    Future<IosNativeConnector> connect() =>
        IosNativeConnector.connect(bootstrap: bootstrap);

    test('tapElement clicks the element found by accessibility id', () async {
      server
        ..on('POST', '/session/sess-1/element', (request) {
          expect(request.body!['using'], 'accessibility id');
          expect(request.body!['value'], 'allow_button');
          return const FakeResponse.value({w3cElementKey: 'el-7'});
        })
        ..onValue('POST', '/session/sess-1/element/el-7/click', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.tapElement(nativeElement(id: 'allow_button'));

      expect(
        server.requestsTo('POST', '/session/sess-1/element/el-7/click'),
        hasLength(1),
      );
    });

    test('tapElement falls back to the element center', () async {
      server
        ..on('POST', '/session/sess-1/element', (_) => _noSuchElement)
        ..onValue('POST', '/session/sess-1/actions', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.tapElement(nativeElement(text: 'OK', x: 10, y: 10));

      expect(
        _pointerStart(
            server.requestsTo('POST', '/session/sess-1/actions').single),
        (x: 60, y: 35),
      );
    });

    test('label lookup builds a valid XPath literal for apostrophes', () async {
      server
        ..on('POST', '/session/sess-1/element', (request) {
          return request.body!['using'] == 'xpath'
              ? const FakeResponse.value({w3cElementKey: 'el-1'})
              : _noSuchElement;
        })
        ..onValue('POST', '/session/sess-1/element/el-1/click', null);
      final connector = await connect();
      addTearDown(connector.dispose);

      await connector.tapElement(nativeElement(text: "Don't Allow"));

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

    test('dispose is idempotent and keeps an injected bootstrap', () async {
      final connector = await connect();

      await connector.dispose();
      await connector.dispose();

      expect(server.requestsTo('DELETE', '/session/sess-1'), hasLength(1));
      expect(bootstrap.disposeCalls, 0);
    });
  });
}
