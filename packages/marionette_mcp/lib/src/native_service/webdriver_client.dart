import 'dart:convert';
import 'dart:io';

/// Exception thrown when a WebDriver endpoint returns a non-2xx HTTP status
/// or a W3C error body.
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

/// W3C WebDriver element identifier key used in element response objects.
///
/// See https://www.w3.org/TR/webdriver/#elements. Older (JSON Wire) servers
/// use `ELEMENT` instead, which [WebDriverClient.findElement] falls back to.
const w3cElementKey = 'element-6066-11e4-a52e-4f735466cecf';

/// Minimal W3C WebDriver HTTP client.
///
/// Speaks the subset of the protocol shared by Appium's UIAutomator2 server
/// (Android) and WebDriverAgent (iOS): session lifecycle, page source,
/// element lookup/click/sendKeys, and W3C pointer actions. Uses `dart:io`
/// [HttpClient] directly so `marionette_mcp` gains no new dependencies.
///
/// All methods throw [WebDriverException] on non-2xx responses or when the
/// server returns a W3C error body (`{"value": {"error": ..., "message":
/// ...}}`).
class WebDriverClient {
  /// Creates a client for a WebDriver server at [baseUrl]
  /// (e.g. `http://127.0.0.1:8100`). A trailing slash is tolerated.
  WebDriverClient(String baseUrl)
      : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _http = HttpClient();

  final String _baseUrl;
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
    // Some legacy servers put sessionId at the top level; _request already
    // unwrapped "value", so also accept a bare string just in case.
    if (value is Map<String, dynamic>) {
      final sessionId = value['sessionId'];
      if (sessionId is String) return sessionId;
    }
    if (value is String) return value;
    throw const WebDriverException(
      'Session created but no sessionId found in response',
    );
  }

  /// Deletes the session, releasing the device-side automation.
  Future<void> deleteSession(String sessionId) async {
    await _request('DELETE', '/session/$sessionId');
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
  /// [WebDriverException] with error `no such element` when nothing matches.
  ///
  /// Sends both W3C (`using`/`value`) and Appium UIAutomator2
  /// (`strategy`/`selector`) fields — standalone UIA2 rejects requests that
  /// only include the W3C pair.
  Future<String> findElement(
    String sessionId,
    String using,
    String value,
  ) async {
    final result = await _request('POST', '/session/$sessionId/element', body: {
      'using': using,
      'value': value,
      'strategy': using,
      'selector': value,
    });

    if (result is Map<String, dynamic>) {
      final elementId = result[w3cElementKey] ?? result['ELEMENT'];
      if (elementId is String) return elementId;
    }
    throw const WebDriverException(
      'Element found but no element id in response',
    );
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

  /// Performs raw W3C actions (https://www.w3.org/TR/webdriver/#actions).
  ///
  /// [actions] is the list of input source objects sent as the `actions`
  /// field; use this for gestures beyond what [swipe] covers.
  Future<void> performActions(
    String sessionId,
    List<Map<String, dynamic>> actions,
  ) async {
    await _request(
      'POST',
      '/session/$sessionId/actions',
      body: {'actions': actions},
    );
  }

  /// Convenience swipe built on [performActions]: a single pointer
  /// sequence that presses down at ([startX], [startY]) and moves to
  /// ([endX], [endY]) over [durationMs] milliseconds.
  ///
  /// Coordinates are in the server's native (physical) pixel space.
  Future<void> swipe(
    String sessionId, {
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
  }) async {
    await performActions(sessionId, [
      {
        'type': 'pointer',
        'id': 'finger1',
        'parameters': {'pointerType': 'touch'},
        'actions': [
          {
            'type': 'pointerMove',
            'duration': 0,
            'x': startX,
            'y': startY,
          },
          {'type': 'pointerDown', 'button': 0},
          {
            'type': 'pointerMove',
            'duration': durationMs,
            'origin': 'viewport',
            'x': endX,
            'y': endY,
          },
          {'type': 'pointerUp', 'button': 0},
        ],
      },
    ]);
  }

  /// Returns WDA device metadata from `GET /wda/device/info` (simulator UDID, etc.).
  Future<Map<String, dynamic>> wdaDeviceInfo() async {
    final value = await _request('GET', '/wda/device/info');
    if (value is Map<String, dynamic>) return value;
    throw const WebDriverException(
      'WDA device info response was not an object',
    );
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
  /// Never throws — intended as a bootstrap health check that is polled
  /// while the device-side server is still starting up.
  Future<bool> status() async {
    try {
      await _request('GET', '/status');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Closes the underlying HTTP client. The instance is unusable afterwards.
  void close() {
    _http.close(force: true);
  }

  /// Sends a request and returns the unwrapped W3C `value` field (or the
  /// whole decoded body when no envelope is present).
  Future<Object?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');

    HttpClientResponse response;
    String responseBody;
    try {
      final request = await _http.openUrl(method, uri);
      if (body != null) {
        // ChromeDriver rejects chunked request bodies, which dart:io uses
        // unless contentLength is set explicitly.
        final payload = utf8.encode(jsonEncode(body));
        request.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        request.contentLength = payload.length;
        request.add(payload);
      }
      response = await request.close();
      responseBody = await utf8.decodeStream(response);
    } on WebDriverException {
      rethrow;
    } catch (e) {
      throw WebDriverException('$method $uri failed: $e');
    }

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
    final isHttpError = response.statusCode < 200 || response.statusCode >= 300;
    if (value is Map<String, dynamic> && value['error'] is String) {
      throw WebDriverException(
        (value['message'] as String?) ?? 'WebDriver error',
        httpStatus: response.statusCode,
        error: value['error'] as String,
      );
    }
    if (isHttpError) {
      throw WebDriverException(
        responseBody.isEmpty ? 'Empty error response' : responseBody,
        httpStatus: response.statusCode,
      );
    }

    return value;
  }
}
