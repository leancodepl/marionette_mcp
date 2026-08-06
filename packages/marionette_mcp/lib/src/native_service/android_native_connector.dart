import 'dart:io';

import 'android_bootstrap.dart';
import 'native_connector.dart';
import 'webdriver_client.dart';

/// Android implementation of [NativeConnector] backed by UIAutomator2.
class AndroidNativeConnector implements NativeConnector {
  AndroidNativeConnector._({
    required AndroidBootstrap bootstrap,
    required WebDriverClient client,
    required String sessionId,
    required ProcessRunner processRunner,
    String? serial,
  })  : _bootstrap = bootstrap,
        _client = client,
        _sessionId = sessionId,
        _run = processRunner,
        _serial = serial;

  final AndroidBootstrap _bootstrap;
  final WebDriverClient _client;
  final String _sessionId;
  final ProcessRunner _run;
  final String? _serial;

  bool _disposed = false;

  /// Starts UIAutomator2 and opens a WebDriver session.
  static Future<AndroidNativeConnector> connect({
    String? serial,
    AndroidBootstrap? bootstrap,
    ProcessRunner? processRunner,
  }) async {
    final runner = processRunner ?? Process.run;
    final ownedBootstrap = bootstrap ??
        (processRunner == null
            ? AndroidBootstrap(serial: serial)
            : AndroidBootstrap(serial: serial, processRunner: processRunner));
    final baseUri = await ownedBootstrap.ensureServerReady();
    final client = WebDriverClient(baseUri.toString());

    try {
      final sessionId = await client.createSession(
        capabilities: const {
          'platformName': 'Android',
          'appium:automationName': 'UiAutomator2',
        },
      );
      return AndroidNativeConnector._(
        bootstrap: ownedBootstrap,
        client: client,
        sessionId: sessionId,
        processRunner: runner,
        serial: serial ?? ownedBootstrap.serial,
      );
    } catch (_) {
      client.close();
      await ownedBootstrap.dispose();
      rethrow;
    }
  }

  @override
  Future<List<NativeElement>> getNativeElements() async {
    final source = await _client.getPageSource(_sessionId);
    return parseAndroidUiDump(source);
  }

  @override
  Future<String?> get foregroundApp async {
    try {
      final result = await _run('adb', [
        if (_serial != null) ...['-s', _serial],
        'shell',
        'dumpsys',
        'window',
        'windows',
      ]);
      if (result.exitCode != 0 || result.stdout is! String) return null;

      final output = result.stdout as String;
      for (final pattern in _foregroundPackagePatterns) {
        final match = pattern.firstMatch(output);
        if (match != null) return match.group(1);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

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
      final literal = _xpathLiteral(visibleText);
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
      await _bootstrap.dispose();
    }
  }
}

final _foregroundPackagePatterns = [
  RegExp(r'mCurrentFocus=.*?\s([\w.]+)/[\w.$]+'),
  RegExp(r'mFocusedApp=.*?\s([\w.]+)/[\w.$]+'),
];

String _xpathLiteral(String value) {
  if (!value.contains("'")) return "'$value'";
  if (!value.contains('"')) return '"$value"';

  final parts = value.split("'");
  return 'concat(${parts.map((part) => "'$part'").join(', "\'", ')})';
}
