import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A request received by [FakeWebDriverServer].
typedef RecordedRequest = ({
  String method,
  String path,
  Map<String, dynamic>? body,
});

/// Response produced by a [FakeWebDriverServer] route.
class FakeResponse {
  /// W3C success envelope `{"value": value}`.
  const FakeResponse.value(Object? value, {this.status = HttpStatus.ok})
      : _json = value,
        _raw = null,
        _error = null,
        _drop = false;

  /// W3C error envelope `{"value": {"error": ..., "message": ...}}`.
  const FakeResponse.error(
    String error,
    String message, {
    this.status = HttpStatus.internalServerError,
  })  : _json = null,
        _raw = null,
        _error = (error, message),
        _drop = false;

  /// Non-JSON body, e.g. a proxy error page.
  const FakeResponse.raw(String body, {required this.status})
      : _json = null,
        _raw = body,
        _error = null,
        _drop = false;

  /// Closes the connection without answering, as a server that crashed
  /// after receiving the request would.
  const FakeResponse.dropConnection()
      : status = 0,
        _json = null,
        _raw = null,
        _error = null,
        _drop = true;

  final int status;
  final Object? _json;
  final String? _raw;
  final (String, String)? _error;
  final bool _drop;

  String get _body {
    if (_raw != null) return _raw;
    final error = _error;
    if (error != null) {
      return jsonEncode({
        'value': {'error': error.$1, 'message': error.$2},
      });
    }
    return jsonEncode({'value': _json});
  }
}

/// Handles one route of [FakeWebDriverServer].
typedef FakeRouteHandler = FutureOr<FakeResponse> Function(
  RecordedRequest request,
);

/// In-process W3C WebDriver server for tests.
///
/// Binds to a random loopback port, records every request, and answers from
/// routes registered with [on] / [onValue]. Unregistered routes answer with
/// the W3C `unknown command` error. By default `/status`, session creation
/// (id [sessionId]) and session deletion are pre-registered.
class FakeWebDriverServer {
  FakeWebDriverServer._(this._server) {
    _server.listen(_handle);
  }

  /// Starts a server; see the class docs for the default routes.
  static Future<FakeWebDriverServer> start({
    bool defaultRoutes = true,
    String sessionId = 'sess-1',
  }) async {
    final server = FakeWebDriverServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server.sessionId = sessionId;
    if (defaultRoutes) {
      server
        ..onValue('GET', '/status', {'ready': true})
        ..onValue('POST', '/session', {
          'sessionId': sessionId,
          'capabilities': <String, dynamic>{},
        })
        ..onValue('DELETE', '/session/$sessionId', null);
    }
    return server;
  }

  final HttpServer _server;
  final Map<String, FakeRouteHandler> _routes = {};

  /// Session id returned by the default `POST /session` route.
  late final String sessionId;

  /// Every request received, in order.
  final List<RecordedRequest> requests = [];

  /// Base URL to pass to `WebDriverClient`.
  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  /// Port the server listens on.
  int get port => _server.port;

  /// Registers [handler] for exact [method] + [path].
  void on(String method, String path, FakeRouteHandler handler) {
    _routes['$method $path'] = handler;
  }

  /// Registers a route answering with a W3C success envelope for [value].
  void onValue(String method, String path, Object? value) {
    on(method, path, (_) => FakeResponse.value(value));
  }

  /// Requests received for [method] + [path].
  List<RecordedRequest> requestsTo(String method, String path) => requests
      .where((request) => request.method == method && request.path == path)
      .toList();

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final body = bytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final recorded = (
      method: request.method,
      path: request.uri.path,
      body: body,
    );
    requests.add(recorded);

    final key = '${request.method} ${request.uri.path}';
    final handler = _routes[key];
    final response = handler == null
        ? FakeResponse.error(
            'unknown command',
            'No handler for $key',
            status: HttpStatus.notFound,
          )
        : await handler(recorded);

    if (response._drop) {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }

    request.response.statusCode = response.status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(response._body);
    await request.response.close();
  }
}
