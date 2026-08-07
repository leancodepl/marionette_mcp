import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/web_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/web_native_connector.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:test/test.dart';

void main() {
  group('WebNativeConnector', () {
    late HttpServer server;
    late Uri baseUri;
    late Map<String, Future<void> Function(HttpRequest, Map<String, dynamic>?)>
        routes;

    setUp(() async {
      routes = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
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
        final handler = routes[key];
        if (handler == null) {
          request.response.statusCode = 404;
          request.response.write(jsonEncode({
            'value': {'error': 'unknown command', 'message': key},
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

    Future<void> writeJson(HttpRequest request, Object? value) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'value': value}));
      await request.response.close();
    }

    test('connect attaches, lists DOM elements, and reads foregroundApp', () async {
      routes['GET /status'] =
          (request, _) => writeJson(request, {'ready': true});
      routes['POST /session'] = (request, body) {
        final caps = body?['capabilities'] as Map<String, dynamic>?;
        final always = caps?['alwaysMatch'] as Map<String, dynamic>?;
        expect(always?['browserName'], 'chrome');
        final chrome = always?['goog:chromeOptions'] as Map<String, dynamic>?;
        expect(chrome?['debuggerAddress'], '127.0.0.1:9222');
        return writeJson(request, {
          'sessionId': 'web-sess',
          'capabilities': <String, dynamic>{},
        });
      };
      routes['GET /session/web-sess/source'] = (request, _) => writeJson(
            request,
            '<html><body><button id="go">Go</button></body></html>',
          );
      routes['GET /session/web-sess/title'] =
          (request, _) => writeJson(request, 'Demo');
      routes['DELETE /session/web-sess'] =
          (request, _) => writeJson(request, null);

      final connector = await WebNativeConnector.connect(
        debuggerAddress: '127.0.0.1:9222',
        bootstrap: WebBootstrap(existingServerUrl: baseUri.toString()),
        processRunner: (_, __) async => ProcessResult(0, 0, '', ''),
      );
      addTearDown(connector.dispose);

      final elements = await connector.getNativeElements();
      expect(elements, hasLength(1));
      expect(elements.single.resourceId, 'go');
      expect(elements.single.text, 'Go');

      expect(await connector.foregroundApp, 'Demo');
    });

    test('connect attaches via debuggerAddress without navigating', () async {
      routes['GET /status'] =
          (request, _) => writeJson(request, {'ready': true});
      routes['POST /session'] = (request, body) {
        final caps = body?['capabilities'] as Map<String, dynamic>?;
        final always = caps?['alwaysMatch'] as Map<String, dynamic>?;
        final chrome = always?['goog:chromeOptions'] as Map<String, dynamic>?;
        expect(chrome?['debuggerAddress'], '127.0.0.1:9222');
        expect(chrome?.containsKey('binary'), isFalse);
        return writeJson(request, {
          'sessionId': 'web-sess',
          'capabilities': <String, dynamic>{},
        });
      };
      routes['GET /session/web-sess/source'] = (request, _) => writeJson(
            request,
            '<html><body><button id="go">Go</button></body></html>',
          );
      routes['DELETE /session/web-sess'] =
          (request, _) => writeJson(request, null);

      final connector = await WebNativeConnector.connect(
        debuggerAddress: '127.0.0.1:9222',
        bootstrap: WebBootstrap(existingServerUrl: baseUri.toString()),
        processRunner: (_, __) async => ProcessResult(0, 0, '', ''),
      );
      addTearDown(connector.dispose);

      expect(await connector.getNativeElements(), hasLength(1));
    });

    test('tapElement clicks by css id', () async {
      routes['GET /status'] =
          (request, _) => writeJson(request, {'ready': true});
      routes['POST /session'] = (request, _) => writeJson(request, {
            'sessionId': 'web-sess',
            'capabilities': <String, dynamic>{},
          });
      routes['POST /session/web-sess/element'] = (request, body) {
        expect(body?['using'], 'css selector');
        expect(body?['value'], '#allow');
        return writeJson(request, {w3cElementKey: 'el-allow'});
      };
      routes['POST /session/web-sess/element/el-allow/click'] =
          (request, _) => writeJson(request, null);
      routes['DELETE /session/web-sess'] =
          (request, _) => writeJson(request, null);

      final connector = await WebNativeConnector.connect(
        debuggerAddress: '127.0.0.1:9222',
        bootstrap: WebBootstrap(existingServerUrl: baseUri.toString()),
        processRunner: (_, __) async => ProcessResult(0, 0, '', ''),
      );
      addTearDown(connector.dispose);

      await connector.tapElement(
        const NativeElement(
          className: 'button',
          clickable: true,
          bounds: NativeBounds(x: 0, y: 0, width: 0, height: 0),
          resourceId: 'allow',
          text: 'Allow',
        ),
      );
    });
  });
}
