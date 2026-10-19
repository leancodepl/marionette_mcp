import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/android_native_device.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';
import 'package:marionette_mcp/src/native_service/xpath.dart';

final _logger = logging.Logger('AndroidNativeConnector');

/// Android implementation of [NativeConnector] backed by UIAutomator2.
final class AndroidNativeConnector extends WebDriverNativeConnector {
  AndroidNativeConnector._({
    required super.client,
    required super.sessionId,
    required super.bootstrap,
    required super.ownsBootstrap,
    required AdbClient adb,
  })  : _adb = adb,
        device = AndroidNativeDevice(adb);

  final AdbClient _adb;

  @override
  final NativeDevice device;

  /// Starts UIAutomator2 (unless [bootstrap] is given) and opens a WebDriver
  /// session.
  ///
  /// A [bootstrap] passed in is not disposed by this connector; the caller
  /// keeps ownership. [adb] defaults to a client for [serial].
  /// How long UIAutomator2 waits for the UI to become idle before reading
  /// the tree or acting. Its default (10 s) made every read on a screen with
  /// continuous animation (video, map, loading thumbnails) take 10 s; 500 ms
  /// still waits out ordinary transitions (docs/native-lane-decisions.md#d18).
  static const waitForIdleTimeoutMs = 500;

  static Future<AndroidNativeConnector> connect({
    String? serial,
    NativeServerBootstrap? bootstrap,
    AdbClient? adb,
  }) async {
    final ownsBootstrap = bootstrap == null;
    final ownedBootstrap =
        ownsBootstrap ? AndroidBootstrap(serial: serial) : null;
    final resolvedBootstrap = bootstrap ?? ownedBootstrap!;
    final resolvedAdb = adb ?? ownedBootstrap?.adb ?? AdbClient(serial: serial);

    final connector = await WebDriverNativeConnector.openSession(
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
    try {
      await connector.client.uia2UpdateSettings(
        connector.sessionId,
        const {'waitForIdleTimeout': waitForIdleTimeoutMs},
      );
    } on WebDriverException catch (error) {
      // A slower session is still a working one.
      _logger.warning('Could not set waitForIdleTimeout: $error');
    }
    return connector;
  }

  @override
  List<NativeElement> parseSource(String xml) => parseAndroidUiDump(xml);

  @override
  String get classAttribute => 'className';

  /// `EditText` and its subclasses (Flutter and Compose fields report
  /// `android.widget.EditText`; Material's `TextInputEditText`,
  /// `AutoCompleteTextView`).
  @override
  bool isEditableClass(String className) =>
      className.contains('EditText') ||
      className.contains('AutoCompleteTextView');

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
  Future<void> enterText(
    NativeElement element,
    String text, {
    bool clear = false,
  }) async {
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
        '//android.widget.EditText[@hint=$literal or @text=$literal or '
            '@content-desc=$literal]',
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
    await typeInto(elementId, text, clear: clear);
  }

  @override
  Future<void> pressKey(NativeKey key) => client.uia2PressKeycode(
        sessionId,
        switch (key) {
          NativeKey.back => 4,
          NativeKey.home => 3,
          NativeKey.enter => 66,
          NativeKey.backspace => 67,
          NativeKey.tab => 61,
          NativeKey.recents => 187,
          NativeKey.volumeUp => 24,
          NativeKey.volumeDown => 25,
        },
      );

  @override
  Future<bool> isKeyboardShown() async {
    final shown = await _adb.isKeyboardShown();
    if (shown == null) {
      throw const NativeOperationFailedException(
        'Could not read the keyboard state (adb dumpsys input_method).',
        hint: 'Check that adb can reach the device.',
      );
    }
    return shown;
  }

  /// Presses Back, which closes a shown IME without navigating. Back is
  /// only sent when the keyboard is shown — otherwise it would navigate.
  @override
  Future<bool> hideKeyboard() async {
    if (!await isKeyboardShown()) return false;
    await pressKey(NativeKey.back);
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!await isKeyboardShown()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const NativeOperationFailedException(
      'The keyboard is still shown after pressing Back.',
      hint: 'Unfocus the field in the app (e.g. tap outside it) and retry.',
    );
  }

  /// Locates [element] by its class and exact bounds (unique even when ids
  /// or texts repeat), then by resource id.
  @override
  Future<String?> locateElement(NativeElement element) async {
    final elementId = await _tryFind('xpath', androidGeometryXPath(element));
    if (elementId != null) return elementId;
    final resourceId = element.resourceId;
    if (resourceId == null) return null;
    return _tryFind('id', resourceId);
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

/// XPath selecting the UIAutomator2 node of [element]'s class at exactly its
/// bounds (`[x1,y1][x2,y2]`, pixels — the same units as the element).
String androidGeometryXPath(NativeElement element) {
  final b = element.bounds;
  return '//*[@class=${xpathLiteral(element.className)} and '
      '@bounds="[${b.x},${b.y}][${b.x + b.width},${b.y + b.height}]"]';
}
