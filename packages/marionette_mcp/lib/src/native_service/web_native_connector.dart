import 'package:marionette_mcp/src/native_service/chrome_debugger_discovery.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/web_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// [NativeConnector] backed by ChromeDriver for browser / Flutter-web DOM.
///
/// Use [connect] to start (or attach to) ChromeDriver and attach to the Chrome
/// session from `flutter run -d chrome`. Flutter widgets painted by CanvasKit are
/// **not** in the DOM — use the Flutter VM lane for those.
class WebNativeConnector implements NativeConnector {
  WebNativeConnector._({
    required WebBootstrap bootstrap,
    required WebDriverClient client,
    required String sessionId,
    required bool ownsBootstrap,
  })  : _bootstrap = bootstrap,
        _client = client,
        _sessionId = sessionId,
        _ownsBootstrap = ownsBootstrap;

  final WebBootstrap _bootstrap;
  final WebDriverClient _client;
  final String _sessionId;
  final bool _ownsBootstrap;

  /// Starts ChromeDriver (unless [chromeDriverUrl] is set), then attaches to
  /// an existing Chrome via [debuggerAddress] / auto-discovery — the same
  /// browser as `flutter run -d chrome`.
  static Future<WebNativeConnector> connect({
    String? chromeDriverUrl,
    String? chromeDriverPath,
    String? debuggerAddress,
    WebBootstrap? bootstrap,
    ProcessRunner? processRunner,
  }) async {
    final ownsBootstrap = bootstrap == null;
    final resolved = bootstrap ??
        WebBootstrap(
          chromeDriverPath: chromeDriverPath,
          existingServerUrl: chromeDriverUrl,
        );
    final baseUri = await resolved.ensureServerReady();
    final client = WebDriverClient(baseUri.toString());

    try {
      final attachAddress = await resolveChromeDebuggerAddress(
        debuggerAddress: debuggerAddress,
        processRunner: processRunner,
      );

      if (attachAddress == null) {
        throw const WebNativeAttachException(webNativeAttachInstructions);
      }

      final sessionId = await client.createSession(
        capabilities: {
          'browserName': 'chrome',
          'goog:chromeOptions': {'debuggerAddress': attachAddress},
        },
      );

      return WebNativeConnector._(
        bootstrap: resolved,
        client: client,
        sessionId: sessionId,
        ownsBootstrap: ownsBootstrap,
      );
    } catch (_) {
      client.close();
      if (ownsBootstrap) {
        await resolved.dispose();
      }
      rethrow;
    }
  }

  @override
  Future<List<NativeElement>> getNativeElements() async {
    final source = await _client.getPageSource(_sessionId);
    return parseHtmlDom(source);
  }

  @override
  Future<String?> get foregroundApp async {
    try {
      final title = await _client.getTitle(_sessionId);
      if (title.trim().isNotEmpty) return title.trim();
    } catch (_) {
      // Fall through to URL.
    }
    try {
      final url = await _client.getUrl(_sessionId);
      final uri = Uri.tryParse(url);
      return uri?.host.isNotEmpty == true ? uri!.host : url;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> tapElement(NativeElement element) async {
    final elementId = await _findDomElement(element);
    if (elementId != null) {
      await _client.elementClick(_sessionId, elementId);
      return;
    }
    final center = element.center;
    if (element.bounds.width > 0 && element.bounds.height > 0) {
      await tapAt(center.x, center.y);
      return;
    }
    throw WebDriverException(
      'Could not locate DOM element to tap '
      '(id=${element.resourceId}, text=${element.text})',
      error: 'no such element',
    );
  }

  @override
  Future<void> tapAt(int x, int y) {
    return _client.swipe(
      _sessionId,
      startX: x,
      startY: y,
      endX: x,
      endY: y,
      durationMs: 50,
      pointerType: 'mouse',
    );
  }

  @override
  Future<void> enterText(NativeElement element, String text) async {
    var elementId = await _findDomElement(element);
    if (elementId == null) {
      await tapElement(element);
      elementId = await _tryFind('css selector', ':focus');
    }
    if (elementId == null) {
      throw const WebDriverException(
        'Could not locate a DOM field for typing',
        error: 'no such element',
      );
    }
    await _client.elementSendKeys(_sessionId, elementId, text);
  }

  @override
  Future<void> swipe({
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
  }) {
    return _client.swipe(
      _sessionId,
      startX: startX,
      startY: startY,
      endX: endX,
      endY: endY,
      durationMs: durationMs,
      pointerType: 'mouse',
    );
  }

  @override
  Future<String> takeScreenshot() => _client.takeScreenshot(_sessionId);

  @override
  Future<void> dispose() async {
    try {
      await _client.deleteSession(_sessionId);
    } catch (_) {
      // Session may already be gone.
    }
    _client.close();
    if (_ownsBootstrap) {
      await _bootstrap.dispose();
    }
  }

  Future<String?> _findDomElement(NativeElement element) async {
    final id = element.resourceId;
    if (id != null && id.isNotEmpty) {
      final found = await _tryFind('css selector', '#${_cssEscapeId(id)}');
      if (found != null) return found;
    }

    final text = element.text;
    if (text != null && text.isNotEmpty) {
      final literal = _xpathLiteral(text);
      final tag = element.className;
      final found = await _tryFind(
        'xpath',
        '//${tag.isNotEmpty ? tag : '*'}'
            '[normalize-space(.)=$literal or @aria-label=$literal '
            'or @placeholder=$literal or @value=$literal or @title=$literal]',
      );
      if (found != null) return found;
      return _tryFind(
        'xpath',
        '//*[normalize-space(.)=$literal or @aria-label=$literal '
            'or @placeholder=$literal or @value=$literal]',
      );
    }
    return null;
  }

  Future<String?> _tryFind(String using, String value) async {
    try {
      return await _client.findElement(_sessionId, using, value);
    } on WebDriverException catch (error) {
      if (error.error == 'no such element' || error.httpStatus == 404) {
        return null;
      }
      rethrow;
    }
  }
}

String _cssEscapeId(String id) {
  return id.replaceAllMapped(
    RegExp(r'([^a-zA-Z0-9_-])'),
    (match) => '\\${match[1]}',
  );
}

String _xpathLiteral(String value) {
  if (!value.contains("'")) return "'$value'";
  if (!value.contains('"')) return '"$value"';
  final parts = value.split("'");
  return 'concat(${parts.map((part) => "'$part'").join(', "\'", ')})';
}
