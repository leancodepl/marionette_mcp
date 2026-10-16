import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';
import 'package:marionette_mcp/src/native_service/xpath.dart';

/// Android implementation of [NativeConnector] backed by UIAutomator2.
final class AndroidNativeConnector extends WebDriverNativeConnector {
  AndroidNativeConnector._({
    required super.client,
    required super.sessionId,
    required super.bootstrap,
    required super.ownsBootstrap,
    required AdbClient adb,
  }) : _adb = adb;

  final AdbClient _adb;

  /// Starts UIAutomator2 (unless [bootstrap] is given) and opens a WebDriver
  /// session.
  ///
  /// A [bootstrap] passed in is not disposed by this connector; the caller
  /// keeps ownership. [adb] defaults to a client for [serial].
  static Future<AndroidNativeConnector> connect({
    String? serial,
    NativeServerBootstrap? bootstrap,
    AdbClient? adb,
  }) {
    final ownsBootstrap = bootstrap == null;
    final ownedBootstrap =
        ownsBootstrap ? AndroidBootstrap(serial: serial) : null;
    final resolvedBootstrap = bootstrap ?? ownedBootstrap!;
    final resolvedAdb = adb ?? ownedBootstrap?.adb ?? AdbClient(serial: serial);

    return WebDriverNativeConnector.openSession(
      bootstrap: resolvedBootstrap,
      ownsBootstrap: ownsBootstrap,
      capabilities: const {
        'platformName': 'Android',
        'appium:automationName': 'UiAutomator2',
      },
      create: (client, sessionId) => AndroidNativeConnector._(
        client: client,
        sessionId: sessionId,
        bootstrap: resolvedBootstrap,
        ownsBootstrap: ownsBootstrap,
        adb: resolvedAdb,
      ),
    );
  }

  @override
  List<NativeElement> parseSource(String xml) => parseAndroidUiDump(xml);

  @override
  Future<String?> get foregroundApp => _adb.foregroundPackage();

  @override
  Future<void> tapElement(NativeElement element) {
    final center = element.center;
    return tapAt(center.x, center.y);
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
    await client.elementSendKeys(sessionId, elementId, text);
  }

  Future<String?> _tryFind(String using, String value) async {
    try {
      return await client.findElement(sessionId, using, value);
    } on WebDriverException catch (error) {
      if (error.error == 'no such element' || error.httpStatus == 404) {
        return null;
      }
      rethrow;
    }
  }
}
