import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:test/test.dart';

typedef _Handler = FutureOr<void> Function(
  HttpRequest request,
  Map<String, dynamic>? body,
);

void main() {
  group('WebDriverClient', () {
    late HttpServer server;
    late Uri baseUri;
    late Map<String, _Handler> routes;
    late List<({String method, String path, Map<String, dynamic>? body})> requests;

    setUp(() async {
      routes = {};
      requests = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
      );

      server.listen((request) async {
        final bodyBytes = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        Map<String, dynamic>? body;
        if (bodyBytes.isNotEmpty) {
          body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
        }

        final key = '${request.method} ${request.uri.path}';
        requests.add((method: request.method, path: request.uri.path, body: body));

        final handler = routes[key];
        if (handler == null) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({
            'value': {
              'error': 'unknown command',
              'message': 'No handler for $key',
            },
          }));
          await request.response.close();
          return;
        }

        await handler(request, body);
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<void> writeJson(
      HttpRequest request,
      Object? value, {
      int status = HttpStatus.ok,
    }) async {
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'value': value}));
      await request.response.close();
    }

    test('status returns true when /status is healthy', () async {
      routes['GET /status'] = (request, _) => writeJson(request, {'ready': true});

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(await client.status(), isTrue);
    });

    test('status returns false on HTTP error without throwing', () async {
      routes['GET /status'] = (request, _) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      };

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(await client.status(), isFalse);
    });

    test('createSession reads W3C value.sessionId', () async {
      routes['POST /session'] = (request, body) {
        expect(body?['capabilities'], isA<Map>());
        return writeJson(request, {
          'sessionId': 'sess-123',
          'capabilities': <String, dynamic>{},
        });
      };

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(await client.createSession(), 'sess-123');
    });

    test('getPageSource returns XML string', () async {
      const xml = '<hierarchy/>';
      routes['GET /session/sess-1/source'] = (request, _) => writeJson(request, xml);

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(await client.getPageSource('sess-1'), xml);
    });

    test('takeScreenshot returns raw base64 PNG payload', () async {
      const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      routes['GET /session/sess-1/screenshot'] = (request, _) => writeJson(request, png);

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(await client.takeScreenshot('sess-1'), png);
    });

    test('takeScreenshot strips data URI prefix when present', () async {
      const png = 'abc123';
      routes['GET /session/sess-1/screenshot'] = (request, _) => writeJson(request, 'data:image/png;base64,$png');

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(await client.takeScreenshot('sess-1'), png);
    });

    test('takeScreenshot rejects empty payload', () async {
      routes['GET /session/sess-1/screenshot'] = (request, _) => writeJson(request, '');

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(
        () => client.takeScreenshot('sess-1'),
        throwsA(isA<WebDriverException>()),
      );
    });

    test('findElement reads W3C element key', () async {
      routes['POST /session/sess-1/element'] = (request, body) {
        expect(body, {
          'using': 'xpath',
          'value': '//Button',
          'strategy': 'xpath',
          'selector': '//Button',
        });
        return writeJson(request, {w3cElementKey: 'el-99'});
      };

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(
        await client.findElement('sess-1', 'xpath', '//Button'),
        'el-99',
      );
    });

    test('findElement falls back to legacy ELEMENT key', () async {
      routes['POST /session/sess-1/element'] = (request, _) => writeJson(request, {'ELEMENT': 'legacy-el'});

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(
        await client.findElement('sess-1', 'id', 'foo'),
        'legacy-el',
      );
    });

    test('elementClick posts to element click endpoint', () async {
      routes['POST /session/sess-1/element/el-1/click'] = (request, _) => writeJson(request, null);

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      await client.elementClick('sess-1', 'el-1');
      expect(
        requests.any((r) => r.path == '/session/sess-1/element/el-1/click'),
        isTrue,
      );
    });

    test('elementSendKeys posts text payload', () async {
      routes['POST /session/sess-1/element/el-1/value'] = (request, body) {
        expect(body, {'text': 'hello'});
        return writeJson(request, null);
      };

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      await client.elementSendKeys('sess-1', 'el-1', 'hello');
    });

    test('swipe builds W3C pointer actions via performActions', () async {
      Map<String, dynamic>? captured;
      routes['POST /session/sess-1/actions'] = (request, body) {
        captured = body;
        return writeJson(request, null);
      };

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      await client.swipe(
        'sess-1',
        startX: 10,
        startY: 20,
        endX: 10,
        endY: 200,
        durationMs: 150,
      );

      final actions = captured!['actions'] as List<dynamic>;
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
      routes['DELETE /session/sess-1'] = (request, _) => writeJson(request, null);

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      await client.deleteSession('sess-1');
      expect(
        requests.any(
          (r) => r.method == 'DELETE' && r.path == '/session/sess-1',
        ),
        isTrue,
      );
    });

    test('W3C error body becomes WebDriverException with error/message', () async {
      routes['POST /session/sess-1/element'] = (request, _) => writeJson(
            request,
            {
              'error': 'no such element',
              'message': 'Element not found',
            },
            status: HttpStatus.notFound,
          );

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

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
      routes['GET /session/sess-1/source'] = (request, _) async {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('upstream down');
        await request.response.close();
      };

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

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
      routes['GET /wda/device/info'] = (request, _) => writeJson(request, {
        'udid': 'SIM-UDID',
        'name': 'iPhone 16',
      });

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(await client.wdaDeviceInfo(), {
        'udid': 'SIM-UDID',
        'name': 'iPhone 16',
      });
    });

    test('wdaActiveAppInfo reads session active app value', () async {
      routes['GET /session/sess-1/wda/activeAppInfo'] =
          (request, _) => writeJson(request, {
                'bundleId': 'com.example.app',
                'processArguments': <dynamic>[],
              });

      final client = WebDriverClient(baseUri.toString());
      addTearDown(client.close);

      expect(
        await client.wdaActiveAppInfo('sess-1'),
        {
          'bundleId': 'com.example.app',
          'processArguments': isEmpty,
        },
      );
    });

    test('close cleans up so further requests fail', () async {
      routes['GET /status'] = (request, _) => writeJson(request, {'ready': true});

      final client = WebDriverClient(baseUri.toString());
      expect(await client.status(), isTrue);

      client.close();

      expect(await client.status(), isFalse);
    });
  });
}
