import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// [NativeConnector] backed by WebDriverAgent on an iOS Simulator.
///
/// Use [connect] to bootstrap WDA (see [IosBootstrap]), open a WebDriver
/// session, and obtain a ready connector. Coordinates are physical pixels.
class IosNativeConnector implements NativeConnector {
  IosNativeConnector._({
    required WebDriverClient client,
    required String sessionId,
    required IosBootstrap bootstrap,
    required bool ownsBootstrap,
  })  : _client = client,
        _sessionId = sessionId,
        _bootstrap = bootstrap,
        _ownsBootstrap = ownsBootstrap;

  final WebDriverClient _client;
  final String _sessionId;
  final IosBootstrap _bootstrap;
  final bool _ownsBootstrap;

  /// Bootstraps WDA (unless [bootstrap] was already prepared), creates a
  /// WebDriver session, and returns a connected connector.
  ///
  /// [udid] selects a simulator when [bootstrap] is omitted. Session
  /// capabilities default to `{platformName: iOS}`, which WDA accepts for an
  /// already-launched runner.
  static Future<IosNativeConnector> connect({
    String? udid,
    IosBootstrap? bootstrap,
    Map<String, dynamic>? capabilities,
  }) async {
    final ownsBootstrap = bootstrap == null;
    final resolved = bootstrap ?? IosBootstrap(udid: udid);
    final baseUri = await resolved.ensureServerReady();

    final client = WebDriverClient(baseUri.toString());
    try {
      final sessionId = await client.createSession(
        capabilities: capabilities ?? const {'platformName': 'iOS'},
      );
      return IosNativeConnector._(
        client: client,
        sessionId: sessionId,
        bootstrap: resolved,
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
    return parseWdaSource(source);
  }

  /// Foreground app identifier derived from the WDA page source.
  ///
  /// There is no reliable WDA `/status`-equivalent for the frontmost bundle
  /// id. We read the first `XCUIElementTypeApplication` node's `name` (falling
  /// back to `label`). Returns null when the source has no Application node.
  @override
  Future<String?> get foregroundApp async {
    final source = await _client.getPageSource(_sessionId);
    return _foregroundAppFromSource(source);
  }

  @override
  Future<void> tapElement(NativeElement element) async {
    final elementId = await _tryFindElement(element);
    if (elementId != null) {
      await _client.elementClick(_sessionId, elementId);
      return;
    }
    final center = element.center;
    await tapAt(center.x, center.y);
  }

  @override
  Future<void> tapAt(int x, int y) async {
    // Zero-length swipe acts as a tap in WDA's W3C actions implementation.
    await _client.swipe(
      _sessionId,
      startX: x,
      startY: y,
      endX: x,
      endY: y,
      durationMs: 50,
    );
  }

  @override
  Future<void> enterText(NativeElement element, String text) async {
    await tapElement(element);

    final elementId = await _tryFindElement(element);
    if (elementId == null) {
      throw WebDriverException(
        'Could not locate element to type into '
        '(id=${element.resourceId}, text=${element.text})',
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
    );
  }

  @override
  Future<String> takeScreenshot() => _client.takeScreenshot(_sessionId);

  @override
  Future<void> dispose() async {
    try {
      await _client.deleteSession(_sessionId);
    } catch (_) {
      // Session may already be gone if WDA died.
    }
    _client.close();
    if (_ownsBootstrap) {
      await _bootstrap.dispose();
    }
  }

  /// Locates the element by accessibility id (`name`) or visible label/text.
  Future<String?> _tryFindElement(NativeElement element) async {
    final id = element.resourceId;
    if (id != null && id.isNotEmpty) {
      try {
        return await _client.findElement(_sessionId, 'accessibility id', id);
      } on WebDriverException {
        // Fall through to name/label strategies.
      }
    }

    final text = element.text;
    if (text != null && text.isNotEmpty) {
      try {
        return await _client.findElement(_sessionId, 'name', text);
      } on WebDriverException {
        // Fall through.
      }
      try {
        // XPath escape: WDA labels rarely contain quotes; double-quote wrap.
        final escaped = text.replaceAll('"', '\\"');
        return await _client.findElement(
          _sessionId,
          'xpath',
          '//*[@label="$escaped" or @name="$escaped" or @value="$escaped"]',
        );
      } on WebDriverException {
        return null;
      }
    }

    return null;
  }
}

/// Reads the frontmost application name/label from WDA XML source.
String? _foregroundAppFromSource(String xml) {
  final apps = parseUiTree(
    xml,
    isRelevant: (attributes) =>
        attributes[uiNodeTagKey] == 'XCUIElementTypeApplication',
  );
  if (apps.isEmpty) return null;

  final attrs = apps.first;
  final name = attrs['name'] ?? '';
  if (name.isNotEmpty) return name;
  final label = attrs['label'] ?? '';
  if (label.isNotEmpty) return label;
  return null;
}
