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

  /// UIAutomator2 works in pixels (scale 1). Its `window/current/size`
  /// matches the screenshot; `adb shell wm size` is the fallback.
  @override
  Future<NativeScreen> getScreen() async {
    try {
      final size = await client.uia2WindowSize(sessionId);
      return NativeScreen(width: size.width, height: size.height, scale: 1);
    } on WebDriverException {
      final size = await _adb.screenSize();
      if (size == null) rethrow;
      return NativeScreen(width: size.width, height: size.height, scale: 1);
    }
  }

  @override
  Future<void> tapElement(NativeElement element) {
    final center = element.center;
    return tapAt(center.x, center.y);
  }

  @override
  Future<void> enterText(NativeElement element, String text) async {
    await tapElement(element);

    // The tap focused exactly the element the selector chose, so the focused
    // field comes first; an id lookup could return another element with the
    // same id (docs/native-lane-decisions.md#d1). Compose-based search bars
    // also expose the hint as a sibling View while the editable node has
    // empty text, which the focused lookup handles too.
    String? elementId = await _tryFind(
      'xpath',
      '//android.widget.EditText[@focused="true"]',
    );
    elementId ??= await _tryFind('xpath', '//*[@focused="true"]');

    final resourceId = element.resourceId;
    if (elementId == null && resourceId != null && resourceId.isNotEmpty) {
      elementId = await _tryFind('id', resourceId);
    }

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
