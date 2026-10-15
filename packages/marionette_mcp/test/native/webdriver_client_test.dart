import 'dart:io';

import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:test/test.dart';

import 'support/fake_webdriver_server.dart';

void main() {
  group('WebDriverClient', () {
    late FakeWebDriverServer server;
    late WebDriverClient client;

    setUp(() async {
      server = await FakeWebDriverServer.start(defaultRoutes: false);
      client = WebDriverClient(server.baseUrl);
    });

    tearDown(() async {
      client.close();
      await server.close();
    });

    test('status returns true when /status is healthy', () async {
      server.onValue('GET', '/status', {'ready': true});

      expect(await client.status(), isTrue);
    });

    test('status returns false on HTTP error without throwing', () async {
      server.on(
        'GET',
        '/status',
        (_) =>
            const FakeResponse.raw('', status: HttpStatus.serviceUnavailable),
      );

      expect(await client.status(), isFalse);
    });

    test('createSession reads W3C value.sessionId', () async {
      server.on('POST', '/session', (request) {
        expect(request.body?['capabilities'], isA<Map<String, dynamic>>());
        return const FakeResponse.value({
          'sessionId': 'sess-123',
          'capabilities': <String, dynamic>{},
        });
      });

      expect(await client.createSession(), 'sess-123');
    });

    test('getPageSource returns XML string', () async {
      const xml = '<hierarchy/>';
      server.onValue('GET', '/session/sess-1/source', xml);

      expect(await client.getPageSource('sess-1'), xml);
    });

    test('takeScreenshot returns raw base64 PNG payload', () async {
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
          'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      server.onValue('GET', '/session/sess-1/screenshot', png);

      expect(await client.takeScreenshot('sess-1'), png);
    });

    test('takeScreenshot strips data URI prefix when present', () async {
      server.onValue(
        'GET',
        '/session/sess-1/screenshot',
        'data:image/png;base64,abc123',
      );

      expect(await client.takeScreenshot('sess-1'), 'abc123');
    });

    test('takeScreenshot rejects empty payload', () async {
      server.onValue('GET', '/session/sess-1/screenshot', '');

      expect(
        () => client.takeScreenshot('sess-1'),
        throwsA(isA<WebDriverException>()),
      );
    });

    test('findElement reads W3C element key', () async {
      server.on('POST', '/session/sess-1/element', (request) {
        expect(request.body, {
          'using': 'xpath',
          'value': '//Button',
          'strategy': 'xpath',
          'selector': '//Button',
        });
        return const FakeResponse.value({w3cElementKey: 'el-99'});
      });

      expect(await client.findElement('sess-1', 'xpath', '//Button'), 'el-99');
    });

    test('findElement falls back to legacy ELEMENT key', () async {
      server.onValue(
        'POST',
        '/session/sess-1/element',
        {'ELEMENT': 'legacy-el'},
      );

      expect(await client.findElement('sess-1', 'id', 'foo'), 'legacy-el');
    });

    test('elementClick posts to element click endpoint', () async {
      server.onValue('POST', '/session/sess-1/element/el-1/click', null);

      await client.elementClick('sess-1', 'el-1');

      expect(
        server.requestsTo('POST', '/session/sess-1/element/el-1/click'),
        hasLength(1),
      );
    });

    test('elementSendKeys posts text payload', () async {
      server.onValue('POST', '/session/sess-1/element/el-1/value', null);

      await client.elementSendKeys('sess-1', 'el-1', 'hello');

      expect(
        server
            .requestsTo('POST', '/session/sess-1/element/el-1/value')
            .single
            .body,
        {'text': 'hello'},
      );
    });

    test('swipe builds W3C pointer actions via performActions', () async {
      server.onValue('POST', '/session/sess-1/actions', null);

      await client.swipe(
        'sess-1',
        startX: 10,
        startY: 20,
        endX: 10,
        endY: 200,
        durationMs: 150,
      );

      final body =
          server.requestsTo('POST', '/session/sess-1/actions').single.body!;
      final actions = body['actions'] as List<dynamic>;
      expect(actions, hasLength(1));
      final source = actions.single as Map<String, dynamic>;
      expect(source['type'], 'pointer');
      expect(source['parameters'], {'pointerType': 'touch'});
      final steps = source['actions'] as List<dynamic>;
      expect(steps[0], {
        'type': 'pointerMove',
        'duration': 0,
        'x': 10,
        'y': 20,
      });
      expect(steps[2], {
        'type': 'pointerMove',
        'duration': 150,
        'origin': 'viewport',
        'x': 10,
        'y': 200,
      });
    });

    test('deleteSession issues DELETE', () async {
      server.onValue('DELETE', '/session/sess-1', null);

      await client.deleteSession('sess-1');

      expect(server.requestsTo('DELETE', '/session/sess-1'), hasLength(1));
    });

    test('W3C error body becomes WebDriverException with error/message',
        () async {
      server.on(
        'POST',
        '/session/sess-1/element',
        (_) => const FakeResponse.error(
          'no such element',
          'Element not found',
          status: HttpStatus.notFound,
        ),
      );

      expect(
        () => client.findElement('sess-1', 'id', 'missing'),
        throwsA(
          isA<WebDriverException>()
              .having((e) => e.error, 'error', 'no such element')
              .having((e) => e.message, 'message', 'Element not found')
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );
    });

    test('non-2xx without W3C body becomes WebDriverException', () async {
      server.on(
        'GET',
        '/session/sess-1/source',
        (_) => const FakeResponse.raw(
          'upstream down',
          status: HttpStatus.badGateway,
        ),
      );

      expect(
        () => client.getPageSource('sess-1'),
        throwsA(
          isA<WebDriverException>()
              .having((e) => e.httpStatus, 'httpStatus', 502)
              .having((e) => e.message, 'message', contains('upstream down')),
        ),
      );
    });

    test('wdaDeviceInfo reads /wda/device/info value', () async {
      server.onValue('GET', '/wda/device/info', {
        'udid': 'SIM-UDID',
        'name': 'iPhone 16',
      });

      expect(await client.wdaDeviceInfo(), {
        'udid': 'SIM-UDID',
        'name': 'iPhone 16',
      });
    });

    test('wdaActiveAppInfo reads session active app value', () async {
      server.onValue('GET', '/session/sess-1/wda/activeAppInfo', {
        'bundleId': 'com.example.app',
        'processArguments': <dynamic>[],
      });

      expect(await client.wdaActiveAppInfo('sess-1'), {
        'bundleId': 'com.example.app',
        'processArguments': isEmpty,
      });
    });

    test('close cleans up so further requests fail', () async {
      server.onValue('GET', '/status', {'ready': true});
      expect(await client.status(), isTrue);

      client.close();

      expect(await client.status(), isFalse);
    });
  });
}
