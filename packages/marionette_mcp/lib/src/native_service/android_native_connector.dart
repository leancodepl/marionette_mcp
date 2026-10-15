import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/xpath.dart';

/// Android implementation of [NativeConnector] backed by UIAutomator2.
class AndroidNativeConnector implements NativeConnector {
  AndroidNativeConnector._({
    required NativeServerBootstrap bootstrap,
    required bool ownsBootstrap,
    required WebDriverClient client,
    required String sessionId,
    required AdbClient adb,
  })  : _bootstrap = bootstrap,
        _ownsBootstrap = ownsBootstrap,
        _client = client,
        _sessionId = sessionId,
        _adb = adb;

  final NativeServerBootstrap _bootstrap;
  final bool _ownsBootstrap;
  final WebDriverClient _client;
  final String _sessionId;
  final AdbClient _adb;

  bool _disposed = false;

  /// Starts UIAutomator2 (unless [bootstrap] is given) and opens a WebDriver
  /// session.
  ///
  /// A [bootstrap] passed in is not disposed by this connector; the caller
  /// keeps ownership. [adb] defaults to a client for [serial].
  static Future<AndroidNativeConnector> connect({
    String? serial,
    NativeServerBootstrap? bootstrap,
    AdbClient? adb,
  }) async {
    final ownsBootstrap = bootstrap == null;
    final AndroidBootstrap? ownedBootstrap =
        ownsBootstrap ? AndroidBootstrap(serial: serial) : null;
    final resolvedBootstrap = bootstrap ?? ownedBootstrap!;
    final resolvedAdb = adb ?? ownedBootstrap?.adb ?? AdbClient(serial: serial);

    final baseUri = await resolvedBootstrap.ensureServerReady();
    final client = WebDriverClient(baseUri.toString());

    try {
      final sessionId = await client.createSession(
        capabilities: const {
          'platformName': 'Android',
          'appium:automationName': 'UiAutomator2',
        },
      );
      return AndroidNativeConnector._(
        bootstrap: resolvedBootstrap,
        ownsBootstrap: ownsBootstrap,
        client: client,
        sessionId: sessionId,
        adb: resolvedAdb,
      );
    } catch (_) {
      client.close();
      if (ownsBootstrap) await resolvedBootstrap.dispose();
      rethrow;
    }
  }

  @override
  Future<List<NativeElement>> getNativeElements() async {
    final source = await _client.getPageSource(_sessionId);
    return parseAndroidUiDump(source);
  }

  @override
  Future<String?> get foregroundApp => _adb.foregroundPackage();

  @override
  Future<void> tapElement(NativeElement element) {
    final center = element.center;
    return tapAt(center.x, center.y);
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
    );
  }

  @override
  Future<void> enterText(NativeElement element, String text) async {
    await tapElement(element);

    String? elementId;
    final resourceId = element.resourceId;
    if (resourceId != null && resourceId.isNotEmpty) {
      elementId = await _tryFind('id', resourceId);
    }

    // Prefer a focused EditText before matching by label text. Compose-based
    // search bars often expose the hint as a sibling View with content-desc
    // (e.g. "Search…") while the actual editable node has empty text.
    elementId ??= await _tryFind(
      'xpath',
      '//android.widget.EditText[@focused="true"]',
    );
    elementId ??= await _tryFind('xpath', '//*[@focused="true"]');

    final visibleText = element.text;
    if (elementId == null && visibleText != null && visibleText.isNotEmpty) {
      final literal = xpathLiteral(visibleText);
      elementId = await _tryFind(
        'xpath',
        '//android.widget.EditText[@text=$literal or @content-desc=$literal]',
      );
      elementId ??= await _tryFind(
        'xpath',
        '//*[@text=$literal or @content-desc=$literal]',
      );
    }

    if (elementId == null) {
      throw const WebDriverException(
        'Tapped the element but could not locate a focused field for typing',
        error: 'no such element',
      );
    }
    await _client.elementSendKeys(_sessionId, elementId, text);
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
    if (_disposed) return;
    _disposed = true;
    try {
      await _client.deleteSession(_sessionId);
    } catch (_) {
      // Continue teardown when the server/session has already disappeared.
    } finally {
      _client.close();
      if (_ownsBootstrap) await _bootstrap.dispose();
    }
  }
}
