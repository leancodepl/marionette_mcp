import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/native_connector.dart';

/// Exception thrown when a WebDriver endpoint returns a non-2xx HTTP status,
/// a W3C error body or a body that is not UTF-8, or when the request fails on
/// I/O: then [error] is [webDriverServerUnreachable] or
/// [webDriverConnectionLost].
///
/// Carries the HTTP status code plus the W3C `error` and `message` fields
/// (when the server provided them) so callers can distinguish, for example,
/// `no such element` from a dead server.
class WebDriverException implements Exception {
  const WebDriverException(
    this.message, {
    this.httpStatus,
    this.error,
  });

  /// Human-readable description, from the W3C `message` field when available.
  final String message;

  /// HTTP status code of the failed response, if a response was received.
  final int? httpStatus;

  /// W3C error code (e.g. `no such element`, `invalid session id`), if any.
  final String? error;

  @override
  String toString() {
    final buffer = StringBuffer('WebDriverException: $message');
    if (error != null) {
      buffer.write(' (error: $error)');
    }
    if (httpStatus != null) {
      buffer.write(' [HTTP $httpStatus]');
    }
    return buffer.toString();
  }
}

/// [WebDriverException.error] used when no connection to the server could be
/// opened within the short timeout, so the request was never sent (not a W3C
/// error code).
const webDriverServerUnreachable = 'server unreachable';

/// [WebDriverException.error] used when the connection broke after the
/// request was sent, or no response arrived within the request's timeout, so
/// the server may have acted on it (not a W3C error code).
///
/// Together with [webDriverServerUnreachable] and the W3C `invalid session
/// id` it signals a lost session.
const webDriverConnectionLost = 'connection lost';

/// W3C error code for a session the server no longer knows.
const webDriverInvalidSessionId = 'invalid session id';

/// W3C error code for a lookup that matched no element.
const webDriverNoSuchElement = 'no such element';

/// W3C error code for an element that is no longer in the UI tree.
const webDriverStaleElementReference = 'stale element reference';

/// W3C error code for an element that cannot take the requested action.
const webDriverInvalidElementState = 'invalid element state';

/// Whether [exception] means the session or its server is gone, so only a
/// new `native_connect` can continue.
bool isLostSession(WebDriverException exception) => switch (exception.error) {
      webDriverInvalidSessionId ||
      webDriverConnectionLost ||
      webDriverServerUnreachable =>
        true,
      _ => false,
    };

/// W3C WebDriver element identifier key used in element response objects.
///
/// See https://www.w3.org/TR/webdriver/#elements.
const w3cElementKey = 'element-6066-11e4-a52e-4f735466cecf';

/// Longest a [WebDriverClient] request may take, from opening the connection
/// to the end of the response body. Longer than the 60 s maximum of
/// `native_wait_for`.
const _defaultRequestTimeout = Duration(seconds: 90);

/// Longest a [WebDriverClient] health check ([WebDriverClient.status]), a
/// teardown ([WebDriverClient.deleteSession]) or the opening of a connection
/// may take, so none of them waits on a hung server.
const webDriverShortTimeout = Duration(seconds: 5);

/// Minimal W3C WebDriver HTTP client.
///
/// Speaks the subset of the protocol shared by Appium's UIAutomator2 server
/// (Android) and WebDriverAgent (iOS): session lifecycle, page source,
/// element lookup/click/sendKeys, and W3C pointer actions. Uses `dart:io`
/// [HttpClient] directly so `marionette_mcp` gains no new dependencies.
///
/// All methods but [status] throw [WebDriverException] on non-2xx responses,
/// on a body that is not UTF-8, or when the server returns a W3C error body
/// (`{"value": {"error": ..., "message": ...}}`). An I/O failure throws one
/// with [webDriverServerUnreachable] when no connection opened, else with
/// [webDriverConnectionLost], as does a request whose response takes longer
/// than its timeout (it is aborted). Any other error is a programmer error
/// and propagates unchanged.
class WebDriverClient {
  /// Creates a client for a WebDriver server at [baseUrl]
  /// (e.g. `http://127.0.0.1:8100`). A trailing slash is tolerated.
  ///
  /// [shortTimeout] bounds [status], [deleteSession] and the opening of
  /// every connection, [requestTimeout] the response to every other request.
  WebDriverClient(
    String baseUrl, {
    Duration requestTimeout = _defaultRequestTimeout,
    Duration shortTimeout = webDriverShortTimeout,
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _requestTimeout = requestTimeout,
        _shortTimeout = shortTimeout,
        _http = HttpClient()..connectionTimeout = shortTimeout;

  final String _baseUrl;
  final Duration _requestTimeout;
  final Duration _shortTimeout;
  final HttpClient _http;

  /// Creates a new session and returns its session id.
  ///
  /// [capabilities] are sent as the W3C `alwaysMatch` capabilities; both
  /// UIAutomator2 and WDA accept an empty map for an already-launched target.
  Future<String> createSession({Map<String, dynamic>? capabilities}) async {
    final value = await _request('POST', '/session', body: {
      'capabilities': {
        'alwaysMatch': capabilities ?? <String, dynamic>{},
      },
    });

    // W3C shape: {"value": {"sessionId": ..., "capabilities": ...}}.
    if (value case {'sessionId': final String sessionId}) return sessionId;
    throw const WebDriverException(
      'Session created but no sessionId found in response',
    );
  }

  /// Deletes the session, releasing the device-side automation. Bounded by
  /// the short timeout, so a shutdown never waits on a hung server.
  Future<void> deleteSession(String sessionId) async {
    await _request('DELETE', '/session/$sessionId', timeout: _shortTimeout);
  }

  /// Returns the current UI hierarchy as an XML string.
  Future<String> getPageSource(String sessionId) async {
    final value = await _request('GET', '/session/$sessionId/source');
    if (value is String) return value;
    throw const WebDriverException('Page source response was not a string');
  }

  /// Takes a PNG screenshot of the device screen and returns it as base64.
  ///
  /// Speaks `GET /session/{id}/screenshot` (W3C). Both UIAutomator2 and WDA
  /// return the raw base64 payload in `value`; a `data:image/png;base64,`
  /// prefix is stripped if a server includes one.
  Future<String> takeScreenshot(String sessionId) async {
    final value = await _request('GET', '/session/$sessionId/screenshot');
    if (value is! String || value.isEmpty) {
      throw const WebDriverException(
        'Screenshot response was not a non-empty base64 string',
      );
    }
    const dataUriPrefix = 'data:image/png;base64,';
    if (value.startsWith(dataUriPrefix)) {
      return value.substring(dataUriPrefix.length);
    }
    return value;
  }

  /// Finds a single element and returns its WebDriver element id.
  ///
  /// [using] is a W3C location strategy (e.g. `xpath`, `accessibility id`,
  /// `-android uiautomator`) and [value] the corresponding selector. Throws
  /// [WebDriverException] with error [webDriverNoSuchElement] when nothing
  /// matches.
  Future<String> findElement(
    String sessionId,
    String using,
    String value,
  ) async {
    final result = await _request(
      'POST',
      '/session/$sessionId/element',
      body: _locatorBody(using, value),
    );
    return _elementId(result);
  }

  /// Finds every element matching [using] and [value] (see [findElement])
  /// and returns their WebDriver element ids; empty when nothing matches.
  Future<List<String>> findElements(
    String sessionId,
    String using,
    String value,
  ) async {
    final result = await _request(
      'POST',
      '/session/$sessionId/elements',
      body: _locatorBody(using, value),
    );
    if (result is! List<Object?>) {
      throw const WebDriverException('Element list response was not a list');
    }
    return result.map(_elementId).toList();
  }

  /// Returns the rect of element [elementId] in server units
  /// (`GET .../element/{id}/rect`).
  Future<NativeBounds> elementRect(String sessionId, String elementId) async {
    final value =
        await _request('GET', '/session/$sessionId/element/$elementId/rect');
    if (value
        case {
          'x': final num x,
          'y': final num y,
          'width': final num width,
          'height': final num height,
        }) {
      return NativeBounds(
        x: x.round(),
        y: y.round(),
        width: width.round(),
        height: height.round(),
      );
    }
    throw const WebDriverException('Element rect response had no x/y/size');
  }

  /// Clicks (taps) the element identified by [elementId].
  Future<void> elementClick(String sessionId, String elementId) async {
    await _request('POST', '/session/$sessionId/element/$elementId/click');
  }

  /// Types [text] into the element identified by [elementId].
  Future<void> elementSendKeys(
    String sessionId,
    String elementId,
    String text,
  ) async {
    await _request(
      'POST',
      '/session/$sessionId/element/$elementId/value',
      body: {'text': text},
    );
  }

  /// Clears the value of the editable element [elementId].
  Future<void> elementClear(String sessionId, String elementId) async {
    await _request('POST', '/session/$sessionId/element/$elementId/clear');
  }

  /// Returns attribute [name] of element [elementId], or null when the
  /// server has no value for it (`GET .../element/{id}/attribute/{name}`).
  Future<String?> elementAttribute(
    String sessionId,
    String elementId,
    String name,
  ) async {
    final value = await _request(
      'GET',
      '/session/$sessionId/element/$elementId/attribute/$name',
    );
    return value?.toString();
  }

  /// Returns the id of the element that has keyboard focus
  /// (`GET /session/{id}/element/active`).
  ///
  /// Throws [WebDriverException] ([webDriverNoSuchElement]) when nothing is
  /// focused.
  Future<String> activeElement(String sessionId) async {
    final result = await _request('GET', '/session/$sessionId/element/active');
    if (result case {w3cElementKey: final String elementId}
        when elementId.isNotEmpty) {
      return elementId;
    }
    throw const WebDriverException(
      'No focused element',
      error: webDriverNoSuchElement,
    );
  }

  /// Updates UIAutomator2 server settings (`POST .../appium/settings`),
  /// e.g. `waitForIdleTimeout`.
  Future<void> uia2UpdateSettings(
    String sessionId,
    Map<String, Object> settings,
  ) async {
    await _request(
      'POST',
      '/session/$sessionId/appium/settings',
      body: {'settings': settings},
    );
  }

  /// Presses an Android key by [keycode] (`KeyEvent.KEYCODE_*`) through
  /// UIAutomator2's `appium/device/press_keycode`.
  Future<void> uia2PressKeycode(String sessionId, int keycode) async {
    await _request(
      'POST',
      '/session/$sessionId/appium/device/press_keycode',
      body: {'keycode': keycode},
    );
  }

  /// Presses an iOS hardware button (`home`, `volumeUp`, `volumeDown`)
  /// through WDA's `wda/pressButton`.
  Future<void> wdaPressButton(String sessionId, String name) async {
    await _request(
      'POST',
      '/session/$sessionId/wda/pressButton',
      body: {'name': name},
    );
  }

  /// Types [text] into whatever has keyboard focus through WDA's `wda/keys`.
  /// Special characters such as `\n` (return) and `\b` (backspace) press
  /// the corresponding keys.
  Future<void> wdaKeys(String sessionId, String text) async {
    await _request(
      'POST',
      '/session/$sessionId/wda/keys',
      body: {
        'value': [text],
      },
    );
  }

  /// Asks WDA to dismiss the software keyboard, trying the keys named in
  /// [keyNames] (e.g. `Done`, `return`) when it has no generic way.
  Future<void> wdaDismissKeyboard(
    String sessionId, {
    List<String> keyNames = const [],
  }) async {
    await _request(
      'POST',
      '/session/$sessionId/wda/keyboard/dismiss',
      body: {if (keyNames.isNotEmpty) 'keyNames': keyNames},
    );
  }

  /// Swipes with one finger through W3C actions
  /// (https://www.w3.org/TR/webdriver/#actions): presses down at
  /// ([startX], [startY]) and moves to ([endX], [endY]) over [durationMs]
  /// milliseconds, then keeps the finger still for [holdMs] before lifting
  /// it (no fling when > 0).
  ///
  /// Coordinates are in the server's own units (pixels for UIAutomator2,
  /// points for WebDriverAgent).
  Future<void> swipe(
    String sessionId, {
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
    int holdMs = 0,
  }) async {
    Map<String, Object> move(int x, int y, int moveMs) => {
          'type': 'pointerMove',
          'duration': moveMs,
          'origin': 'viewport',
          'x': x,
          'y': y,
        };

    await _request('POST', '/session/$sessionId/actions', body: {
      'actions': [
        {
          'type': 'pointer',
          'id': 'finger1',
          'parameters': {'pointerType': 'touch'},
          'actions': [
            move(startX, startY, 0),
            {'type': 'pointerDown', 'button': 0},
            move(endX, endY, durationMs),
            if (holdMs > 0) {'type': 'pause', 'duration': holdMs},
            {'type': 'pointerUp', 'button': 0},
          ],
        },
      ],
    });
  }

  /// Screen orientation (`PORTRAIT` / `LANDSCAPE`) from
  /// `GET /session/{id}/orientation`.
  Future<String> getOrientation(String sessionId) async {
    final value = await _request('GET', '/session/$sessionId/orientation');
    if (value is String) return value;
    throw WebDriverException('Unexpected orientation: $value');
  }

  /// Returns the window size from UIAutomator2's
  /// `GET /session/{id}/window/current/size` (pixels). UIAutomator2 does not
  /// implement the W3C `window/rect`.
  Future<({int width, int height})> uia2WindowSize(String sessionId) async {
    final value =
        await _request('GET', '/session/$sessionId/window/current/size');
    final size = _sizeOf(value);
    if (size != null) return size;
    throw const WebDriverException('Window size response had no width/height');
  }

  /// Returns WDA's `GET /session/{id}/wda/screen`: screen size in points and
  /// the display scale (screen pixels per point).
  Future<({int width, int height, double scale})> wdaScreen(
    String sessionId,
  ) async {
    final value = await _request('GET', '/session/$sessionId/wda/screen');
    if (value is Map<String, dynamic>) {
      final size = _sizeOf(value['screenSize']);
      final scale = value['scale'];
      if (size != null && scale is num && scale > 0) {
        return (
          width: size.width,
          height: size.height,
          scale: scale.toDouble()
        );
      }
    }
    throw const WebDriverException('WDA screen response had no size/scale');
  }

  static ({int width, int height})? _sizeOf(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final width = value['width'];
    final height = value['height'];
    if (width is! num || height is! num) return null;
    return (width: width.round(), height: height.round());
  }

  /// Returns the foreground app's bundle id from WDA
  /// `GET /session/{id}/wda/activeAppInfo`.
  Future<Map<String, dynamic>> wdaActiveAppInfo(String sessionId) async {
    final value =
        await _request('GET', '/session/$sessionId/wda/activeAppInfo');
    if (value is Map<String, dynamic>) return value;
    throw const WebDriverException(
      'WDA activeAppInfo response was not an object',
    );
  }

  /// Returns true when the server responds successfully to `GET /status`.
  ///
  /// Returns false instead of throwing a [WebDriverException] — intended as a
  /// bootstrap health check that is polled while the device-side server is
  /// still starting up. Other errors propagate.
  Future<bool> status() async {
    try {
      await _request('GET', '/status', timeout: _shortTimeout);
      return true;
    } on WebDriverException {
      return false;
    }
  }

  /// Closes the underlying HTTP client. The instance is unusable afterwards.
  void close() {
    _http.close(force: true);
  }

  /// The body of a find request for [using] and [value].
  ///
  /// Holds both the W3C (`using`/`value`) and the Appium UIAutomator2
  /// (`strategy`/`selector`) fields: standalone UIA2 rejects requests that
  /// only include the W3C pair.
  static Map<String, dynamic> _locatorBody(String using, String value) => {
        'using': using,
        'value': value,
        'strategy': using,
        'selector': value,
      };

  /// The element id of a W3C element response object.
  static String _elementId(Object? element) {
    if (element case {w3cElementKey: final String elementId}) return elementId;
    throw const WebDriverException(
      'Element found but no element id in response',
    );
  }

  /// Sends a request and returns the unwrapped W3C `value` field (or the
  /// whole decoded body when no envelope is present).
  ///
  /// Opening the connection takes at most the client's short timeout;
  /// sending and reading the body take at most [timeout] (the client's
  /// request timeout by default).
  Future<Object?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    final limit = timeout ?? _requestTimeout;
    final payload = body == null ? null : utf8.encode(jsonEncode(body));
    final request = await _open(method, Uri.parse('$_baseUrl$path'));
    final (:statusCode, body: responseBody) =
        await _send(request, payload).timeout(
      limit,
      onTimeout: () {
        request.abort();
        throw WebDriverException(
          '$method ${request.uri} got no response within '
          '${limit.inMilliseconds} ms',
          error: webDriverConnectionLost,
        );
      },
    );

    Object? decoded;
    if (responseBody.isNotEmpty) {
      try {
        decoded = jsonDecode(responseBody);
      } on FormatException {
        // Some servers return plain text on hard failures; surface it below.
        decoded = null;
      }
    }

    final value =
        decoded is Map<String, dynamic> && decoded.containsKey('value')
            ? decoded['value']
            : decoded;

    // W3C error bodies look like {"value": {"error": ..., "message": ...}}.
    // Check for them even on 2xx responses — some servers get the status
    // code wrong.
    final isHttpError = statusCode < 200 || statusCode >= 300;
    if (value is Map<String, dynamic> && value['error'] is String) {
      throw WebDriverException(
        (value['message'] as String?) ?? 'WebDriver error',
        httpStatus: statusCode,
        error: value['error'] as String,
      );
    }
    if (isHttpError) {
      throw WebDriverException(
        responseBody.isEmpty ? 'Empty error response' : responseBody,
        httpStatus: statusCode,
      );
    }

    return value;
  }

  /// Opens a connection for [method] [uri].
  Future<HttpClientRequest> _open(String method, Uri uri) async {
    // dart:io connects inside openUrl, so a failure here means the request
    // never left this process — unlike failures in [_send].
    try {
      return await _http.openUrl(method, uri);
    } on IOException catch (e) {
      throw WebDriverException(
        '$method $uri failed: $e',
        error: webDriverServerUnreachable,
      );
    }
  }

  /// Sends [request] with the JSON [payload] and returns the response status
  /// code and body.
  Future<({int statusCode, String body})> _send(
    HttpClientRequest request,
    List<int>? payload,
  ) async {
    try {
      if (payload != null) {
        request.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        request.contentLength = payload.length;
        request.add(payload);
      }
      final response = await request.close();
      return (
        statusCode: response.statusCode,
        body: await utf8.decodeStream(response),
      );
    } on IOException catch (e) {
      // Reset / closed connections (SocketException, HttpException) mean the
      // device-side server went away, possibly after acting on the request.
      throw WebDriverException(
        '${request.method} ${request.uri} failed: $e',
        error: webDriverConnectionLost,
      );
    } on FormatException catch (e) {
      // Not a WebDriver server, e.g. a stale forward to another service.
      throw WebDriverException(
        '${request.method} ${request.uri} answered with a body that is not '
        'UTF-8: ${e.message}',
      );
    }
  }
}
