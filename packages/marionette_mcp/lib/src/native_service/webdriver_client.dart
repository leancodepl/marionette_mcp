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

/// [WebDriverException.error] used when no connection to the server could be
/// opened, so the request was never sent (not a W3C error code).
const webDriverServerUnreachable = 'server unreachable';

/// [WebDriverException.error] used when the connection broke after the
/// request was sent, so the server may have acted on it (not a W3C error
/// code).
///
/// Together with [webDriverServerUnreachable] and the W3C `invalid session
/// id` it signals a lost session; see docs/native-lane-decisions.md#d3.
const webDriverConnectionLost = 'connection lost';

/// W3C error code for a session the server no longer knows.
const webDriverInvalidSessionId = 'invalid session id';

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

  /// Clears the value of the editable element [elementId].
  Future<void> elementClear(String sessionId, String elementId) async {
    await _request('POST', '/session/$sessionId/element/$elementId/clear');
  }

  /// PNG (base64) of just element [elementId]
  /// (`GET /session/{id}/element/{eid}/screenshot`), in the same pixel grid
  /// as [takeScreenshot] on both servers.
  Future<String> elementScreenshot(String sessionId, String elementId) async {
    final value = await _request(
      'GET',
      '/session/$sessionId/element/$elementId/screenshot',
    );
    if (value is String && value.isNotEmpty) return value;
    throw const WebDriverException('Element screenshot was empty');
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
  /// Throws [WebDriverException] (`no such element`) when nothing is focused.
  Future<String> activeElement(String sessionId) async {
    final result = await _request('GET', '/session/$sessionId/element/active');
    if (result is Map<String, dynamic>) {
      final elementId = result[w3cElementKey] ?? result['ELEMENT'];
      if (elementId is String && elementId.isNotEmpty) return elementId;
    }
    throw const WebDriverException(
      'No focused element',
      error: 'no such element',
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

  /// Performs a touch gesture with one pointer per entry of [fingers], all
  /// running in parallel. Each finger is a list of W3C pointer actions; see
  /// [TouchStep] for building them. Coordinates are in server units.
  Future<void> touchActions(
    String sessionId,
    List<List<Map<String, dynamic>>> fingers,
  ) =>
      performActions(sessionId, [
        for (final (i, steps) in fingers.indexed)
          {
            'type': 'pointer',
            'id': 'finger${i + 1}',
            'parameters': {'pointerType': 'touch'},
            'actions': steps,
          },
      ]);

  /// Convenience swipe built on [performActions]: a single pointer
  /// sequence that presses down at ([startX], [startY]) and moves to
  /// ([endX], [endY]) over [durationMs] milliseconds, then keeps the finger
  /// still for [holdMs] before lifting it (no fling when > 0).
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
  }) =>
      touchActions(sessionId, [
        [
          TouchStep.move(startX, startY),
          TouchStep.down(),
          TouchStep.move(endX, endY, durationMs: durationMs),
          if (holdMs > 0) TouchStep.pause(holdMs),
          TouchStep.up(),
        ],
      ]);

  /// Screen orientation (`PORTRAIT` / `LANDSCAPE`) from
  /// `GET /session/{id}/orientation`.
  Future<String> getOrientation(String sessionId) async {
    final value = await _request('GET', '/session/$sessionId/orientation');
    if (value is String) return value;
    throw WebDriverException('Unexpected orientation: $value');
  }

  /// Rotates the screen (`POST /session/{id}/orientation`).
  Future<void> setOrientation(String sessionId, String orientation) async {
    await _request(
      'POST',
      '/session/$sessionId/orientation',
      body: {'orientation': orientation},
    );
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
  /// the display scale (screenshot pixels per point).
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

  /// Returns the W3C window rect size (`GET /session/{id}/window/rect`).
  Future<({int width, int height})> windowRectSize(String sessionId) async {
    final value = await _request('GET', '/session/$sessionId/window/rect');
    final size = _sizeOf(value);
    if (size != null) return size;
    throw const WebDriverException('Window rect response had no width/height');
  }

  static ({int width, int height})? _sizeOf(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final width = value['width'];
    final height = value['height'];
    if (width is! num || height is! num) return null;
    return (width: width.round(), height: height.round());
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

    // dart:io connects inside openUrl, so a failure here means the request
    // never left this process — unlike failures after it is sent below.
    final HttpClientRequest request;
    try {
      request = await _http.openUrl(method, uri);
    } on IOException catch (e) {
      throw WebDriverException(
        '$method $uri failed: $e',
        error: webDriverServerUnreachable,
      );
    } catch (e) {
      throw WebDriverException('$method $uri failed: $e');
    }

    HttpClientResponse response;
    String responseBody;
    try {
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
    } on IOException catch (e) {
      // Reset / closed connections (SocketException, HttpException) mean the
      // device-side server went away, possibly after acting on the request.
      throw WebDriverException(
        '$method $uri failed: $e',
        error: webDriverConnectionLost,
      );
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

/// Width and height of a base64-encoded PNG, read from its IHDR chunk, or
/// null when [pngBase64] is not a PNG.
({int width, int height})? pngSize(String pngBase64) {
  // Signature (8 bytes) + IHDR length/type (8 bytes) + width + height.
  const headerLength = 24;
  final List<int> bytes;
  try {
    // 32 base64 characters decode to exactly 24 bytes.
    bytes = base64Decode(pngBase64.substring(0, 32));
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < headerLength) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  int readUint32(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  return (width: readUint32(16), height: readUint32(20));
}

/// Builders for the W3C pointer actions passed to
/// [WebDriverClient.touchActions].
abstract final class TouchStep {
  /// Moves the finger to ([x], [y]) over [durationMs].
  static Map<String, dynamic> move(int x, int y, {int durationMs = 0}) => {
        'type': 'pointerMove',
        'duration': durationMs,
        'origin': 'viewport',
        'x': x,
        'y': y,
      };

  /// Puts the finger down at its current position.
  static Map<String, dynamic> down() => {'type': 'pointerDown', 'button': 0};

  /// Lifts the finger.
  static Map<String, dynamic> up() => {'type': 'pointerUp', 'button': 0};

  /// Keeps the finger where it is (down or up) for [durationMs].
  static Map<String, dynamic> pause(int durationMs) =>
      {'type': 'pause', 'duration': durationMs};
}
