import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/android_native_device.dart';
import 'package:marionette_mcp/src/native_service/android_ui_dump.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/poll.dart';
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

  /// How long UIAutomator2 waits for the UI to become idle before reading
  /// the tree or acting. Its default (10 s) made every read on a screen with
  /// continuous animation (video, map, loading thumbnails) take 10 s; 500 ms
  /// still waits out ordinary transitions.
  static const waitForIdleTimeoutMs = 500;

  /// How long a tree read keeps retrying while a toast is on screen; a long
  /// toast stays 3.5 s.
  static const toastRetryWindow = Duration(seconds: 5);

  /// Pause between tree reads while a toast is shown.
  static const _toastRetryDelay = Duration(milliseconds: 500);

  /// Keyboards covering less than this share of their window are Gboard's
  /// floating toolbar (hardware keyboard attached), which does not consume
  /// Back.
  static const _floatingKeyboardCoverage = 0.1;

  /// How often and how long [hideKeyboard] checks that the IME closed after
  /// Back (the last check at 1.8 s).
  static const _keyboardCloseChecks = 10;
  static const _keyboardCloseCheckInterval = Duration(milliseconds: 200);

  final AdbClient _adb;
  final bool _sharedServer;

  @override
  final NativeDevice device;

  /// UIAutomator2 (10.3.2) stops itself when its session is deleted, so a
  /// session on a server another process started (reuse — an MCP server,
  /// a CLI session) is left alone; that process ends it.
  @override
  bool get deletesSessionOnDispose => !_sharedServer;

  @override
  String get classAttribute => 'className';

  @override
  Future<String?> get foregroundApp => _adb.foregroundPackage();

  /// Starts UIAutomator2 (unless [bootstrap] is given) and opens a WebDriver
  /// session.
  ///
  /// A [bootstrap] passed in is not disposed by this connector; the caller
  /// keeps ownership. [adb] defaults to a client for [serial].
  static Future<AndroidNativeConnector> connect({
    String? serial,
    NativeServerBootstrap? bootstrap,
    AdbClient? adb,
    String? sessionId,
  }) async {
    final owns = bootstrap == null;
    final ownedBootstrap = owns ? AndroidBootstrap(serial: serial) : null;
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

  /// While a toast is shown, UIAutomator2 fails every page source with
  /// "Cannot set AccessibilityNodeInfo's field 'mSealed'" (seen on API 35;
  /// on API 28 it adds the toast to the tree instead). Only that failure is
  /// retried, for up to [toastRetryWindow]. On API 36 the read times out
  /// instead, and the timeout is not retried.
  @override
  Future<List<NativeElement>> getNativeElements() async {
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        return await super.getNativeElements();
      } on WebDriverException catch (error) {
        if (!_isToastReadFailure(error)) rethrow;
        if (stopwatch.elapsed >= toastRetryWindow) {
          throw NativeOperationFailedException(
            'The UI tree cannot be read right now: $error',
            hint: 'A toast is probably on screen — on this Android version '
                'UIAutomator2 cannot read the tree until it disappears, nor '
                'list the toast. Read the toast with native_take_screenshot, '
                'then retry.',
          );
        }
        await Future<void>.delayed(_toastRetryDelay);
      }
    }
  }

  @override
  bool isEditableClass(String className) => isAndroidEditableClass(className);

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

  /// Taps [element] and types into the field found after the tap (see
  /// [_findField]) when its rect holds the tap point or the tap moved the
  /// focus to it; the parsed bounds are clipped to the screen and the server
  /// rect is not, so the two need not be equal.
  @override
  Future<void> enterText(
    NativeElement element,
    String text, {
    bool clear = false,
  }) async {
    // No focused element is normal before the first text-field tap.
    final focusedBeforeTap = await activeElementOrNull();
    final tapPoint = element.center;
    await tapElement(element);

    var field = await _tappedField(element, tapPoint, focusedBeforeTap);
    if (field == null || !field.tapped) {
      // The focus may still be moving to the tapped field.
      _logger.info(
        'No field found for typing at the tapped point; looking again',
      );
      await Future<void>.delayed(changedFieldRetryDelay);
      field = await _tappedField(element, tapPoint, focusedBeforeTap);
    }
    const settleHint = 'Scroll the field fully into view, wait until the '
        'screen has settled, then retry.';
    switch (field) {
      case null:
        throw NativeOperationFailedException(
          'No text field took the focus after the tap at '
          '(${tapPoint.x}, ${tapPoint.y}); nothing was typed.',
          hint: settleHint,
        );
      case (id: _, tapped: false):
        throw NativeOperationFailedException(
          'The field found for typing is not at the tapped point '
          '(${tapPoint.x}, ${tapPoint.y}); nothing was typed.',
          hint: 'Another field probably kept the focus. $settleHint',
        );
      case (:final id, tapped: true):
        await typeInto(id, text, clear: clear);
    }
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
  /// only sent when the keyboard is shown — otherwise it would navigate —
  /// and not to Gboard's floating toolbar, which lets Back through to the
  /// app.
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
    final closed = await pollUntil(
      () async => !await isKeyboardShown(),
      attempts: _keyboardCloseChecks,
      interval: _keyboardCloseCheckInterval,
    );
    if (closed) return true;
    throw const NativeOperationFailedException(
      'The keyboard is still shown after pressing Back.',
      hint: 'Unfocus the field in the app (e.g. tap outside it) and retry.',
    );
  }

  /// Whether [error] is UIAutomator2's failure while a toast is shown.
  static bool _isToastReadFailure(WebDriverException error) =>
      error.message.contains("AccessibilityNodeInfo's field 'mSealed'");

  /// The id of the field found for typing after tapping [element] at
  /// [tapPoint] (see [_findField]), and whether the tap reached it
  /// (`tapped`): its rect holds [tapPoint], or the tap moved the focus to
  /// it. Null when no field is found.
  Future<({String id, bool tapped})?> _tappedField(
    NativeElement element,
    ({int x, int y}) tapPoint,
    String? focusedBeforeTap,
  ) async {
    final field = await _findField(element);
    if (field == null) return null;
    final rect = await client.elementRect(sessionId, field.id);
    return (
      id: field.id,
      tapped: rect.contains(tapPoint.x, tapPoint.y) ||
          (field.focused && field.id != focusedBeforeTap),
    );
  }

  /// The field to type into after tapping [element]: its WebDriver `id`, and
  /// whether a focused-field lookup found it (`focused`) rather than the id
  /// or text lookup of [element]; null when no lookup finds a field.
  Future<({String id, bool focused})?> _findField(
    NativeElement element,
  ) async {
    // The field that received focus comes first; an id lookup could return
    // another element with the same id. Compose-based search bars also
    // expose the hint as a sibling View while the editable node has empty
    // text, which the focused lookup handles too.
    String? elementId = await _tryFind(
      'xpath',
      '//android.widget.EditText[@focused="true"]',
    );
    if (elementId == null) {
      final anyFocused = await _tryFind('xpath', '//*[@focused="true"]');
      // A focused host or container is no proof that the tap focused a
      // field, so only an editable class counts; otherwise the id and text
      // lookups below run with their tap-point check.
      if (anyFocused != null && await _isEditable(anyFocused)) {
        elementId = anyFocused;
      }
    }
    final focused = elementId != null;

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

    return elementId == null ? null : (id: elementId, focused: focused);
  }

  /// Whether the server reports [elementId] with an editable class.
  Future<bool> _isEditable(String elementId) async {
    final className = await classOf(elementId);
    return className != null && isEditableClass(className);
  }

  Future<String?> _tryFind(String using, String value) async {
    try {
      return await client.findElement(sessionId, using, value);
    } on WebDriverException catch (error) {
      if (!WebDriverNativeConnector.isNoSuchElement(error)) rethrow;
      return null;
    }
  }
}
