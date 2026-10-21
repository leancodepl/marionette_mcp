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
    required bool sharedServer,
  })  : _adb = adb,
        _sharedServer = sharedServer,
        device = AndroidNativeDevice(adb);

  final AdbClient _adb;
  final bool _sharedServer;

  /// UIAutomator2 (10.3.2) stops itself when its session is deleted, so a
  /// session on a server another process started (D10 reuse — an MCP server,
  /// a CLI session) is left alone; that process ends it
  /// (docs/native-lane-decisions.md#d10).
  @override
  bool get deletesSessionOnDispose => !_sharedServer;

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
    String? sessionId,
    bool? ownsBootstrap,
  }) async {
    final owns = ownsBootstrap ?? bootstrap == null;
    final ownedBootstrap =
        bootstrap == null ? AndroidBootstrap(serial: serial) : null;
    final resolvedBootstrap = bootstrap ?? ownedBootstrap!;
    final resolvedAdb = adb ?? ownedBootstrap?.adb ?? AdbClient(serial: serial);

    final connector = await WebDriverNativeConnector.openSession(
      bootstrap: resolvedBootstrap,
      ownsBootstrap: owns,
      capabilities: const {
        'platformName': 'Android',
        'appium:automationName': 'UiAutomator2',
      },
      sessionId: sessionId,
      create: (client, id) => AndroidNativeConnector._(
        client: client,
        sessionId: id,
        bootstrap: resolvedBootstrap,
        ownsBootstrap: owns,
        adb: resolvedAdb,
        sharedServer: resolvedBootstrap is SharedServerBootstrap &&
            !resolvedBootstrap.startedServer,
      ),
    );
    // A reused session already has the setting.
    if (connector.sessionId == sessionId) return connector;
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

  /// How long a tree read keeps retrying while a toast is on screen; a long
  /// toast stays 3.5 s.
  static const toastRetryWindow = Duration(seconds: 5);

  /// While a toast is shown, UIAutomator2 fails every page source with
  /// "Cannot set AccessibilityNodeInfo's field 'mSealed'" (seen on API 35;
  /// on API 28 it adds the toast to the tree instead). Reads are retried
  /// until it is gone (docs/native-lane-decisions.md#d19).
  @override
  Future<List<NativeElement>> getNativeElements() async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        return await super.getNativeElements();
      } on WebDriverException catch (error) {
        if (!isToastReadFailure(error)) rethrow;
        if (stopwatch.elapsed >= toastRetryWindow) {
          throw NativeOperationFailedException(
            'The UI tree cannot be read right now: $error',
            hint: 'A toast is probably on screen — on this Android version '
                'UIAutomator2 cannot read the tree until it disappears, nor '
                'list the toast. Read the toast with native_take_screenshot, '
                'then retry.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// Whether [error] is UIAutomator2's failure while a toast is shown.
  static bool isToastReadFailure(WebDriverException error) =>
      error.message.contains("AccessibilityNodeInfo's field 'mSealed'");

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

  /// Keyboards covering less than this share of their window are Gboard's
  /// floating toolbar (hardware keyboard attached), which does not consume
  /// Back.
  static const _floatingKeyboardCoverage = 0.1;

  /// Presses Back, which closes a shown IME without navigating. Back is
  /// only sent when the keyboard is shown — otherwise it would navigate —
  /// and not to Gboard's floating toolbar, which lets Back through to the
  /// app (docs/native-lane-decisions.md#d14).
  @override
  Future<bool> hideKeyboard() async {
    if (!await isKeyboardShown()) return false;
    final coverage = await _adb.keyboardCoverage();
    if (coverage != null && coverage < _floatingKeyboardCoverage) {
      throw const NativeOperationFailedException(
        'The keyboard is shown only as a floating toolbar (a hardware '
        'keyboard is attached); Back would close the current screen instead '
        'of the keyboard, so nothing was pressed.',
        hint: 'The toolbar covers little of the app. To remove it, unfocus '
            'the field in the app (tap outside it, the app\'s Done button, '
            'or via the Flutter lane), or start the emulator without a '
            'hardware keyboard (AVD hw.keyboard=no).',
      );
    }
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
