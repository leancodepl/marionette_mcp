import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/ios_native_device.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/poll.dart';
import 'package:marionette_mcp/src/native_service/wda_source.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';
import 'package:marionette_mcp/src/native_service/xpath.dart';

/// [NativeConnector] backed by WebDriverAgent on an iOS Simulator.
///
/// Use [connect] to bootstrap WDA (see [IosBootstrap]), open a WebDriver
/// session, and obtain a ready connector.
///
/// WebDriverAgent reports and accepts coordinates in points; this connector
/// converts them to screen pixels with the display scale read at
/// connect time.
final class IosNativeConnector extends WebDriverNativeConnector {
  IosNativeConnector._({
    required super.client,
    required super.sessionId,
    required super.bootstrap,
    required super.ownsBootstrap,
  });

  /// Keys that dismiss the keyboard without editing the text. `return` is
  /// deliberately absent: in a multi-line field it inserts a newline.
  static const _dismissKeyNames = ['Done', 'done', 'Hide keyboard', 'Dismiss'];

  /// How often and how long [hideKeyboard] checks that the keyboard closed
  /// after a dismiss (the last check at 0.8 s).
  static const _keyboardCloseChecks = 5;
  static const _keyboardCloseCheckInterval = Duration(milliseconds: 200);

  /// The Notification Center needs a gesture on iOS (see [IosNativeDevice]).
  @override
  late final NativeDevice device = IosNativeDevice(this);

  /// Screen pixels per point; read from `wda/screen` during [connect].
  double _scale = 1;

  @override
  double get serverUnitScale => _scale;

  /// Bootstraps WDA (unless [bootstrap] was already prepared), creates a
  /// WebDriver session, and returns a connected connector.
  ///
  /// [udid] selects a simulator when [bootstrap] is omitted. A [bootstrap]
  /// passed in is not disposed by this connector; the caller keeps
  /// ownership. Session capabilities default to `{platformName: iOS}`, which
  /// WDA accepts for an already-launched runner.
  static Future<IosNativeConnector> connect({
    String? udid,
    NativeServerBootstrap? bootstrap,
    Map<String, dynamic>? capabilities,
    String? sessionId,
    bool? ownsBootstrap,
  }) async {
    final owns = ownsBootstrap ?? bootstrap == null;
    final resolvedBootstrap = bootstrap ?? IosBootstrap(udid: udid);

    final connector = await WebDriverNativeConnector.openSession(
      bootstrap: resolvedBootstrap,
      ownsBootstrap: owns,
      capabilities: capabilities ?? const {'platformName': 'iOS'},
      sessionId: sessionId,
      create: (client, id) => IosNativeConnector._(
        client: client,
        sessionId: id,
        bootstrap: resolvedBootstrap,
        ownsBootstrap: owns,
      ),
    );
    try {
      final screen = await connector.client.wdaScreen(connector.sessionId);
      connector._scale = screen.scale;
    } catch (_) {
      await connector.dispose();
      rethrow;
    }
    return connector;
  }

  @override
  Future<NativeScreen> getScreen() async {
    final screen = await client.wdaScreen(sessionId);
    return NativeScreen(
      width: (screen.width * _scale).round(),
      height: (screen.height * _scale).round(),
      scale: _scale,
    );
  }

  @override
  List<NativeElement> parseSource(String xml) => parseWdaSource(xml);

  @override
  String get classAttribute => 'type';

  @override
  bool isEditableClass(String className) => isWdaEditableClass(className);

  /// Foreground app bundle identifier from WDA's active-app endpoint, with
  /// page-source fallback when that endpoint is unavailable.
  @override
  Future<String?> get foregroundApp async {
    try {
      final info = await client.wdaActiveAppInfo(sessionId);
      final bundleId = info['bundleId'];
      if (bundleId is String && bundleId.isNotEmpty) return bundleId;
    } on WebDriverException {
      // Fall back to page source parsing below.
    }

    final source = await client.getPageSource(sessionId);
    return foregroundAppFromWdaSource(source);
  }

  /// Taps the center of [element]. Re-locating it through WDA (by id or
  /// label) could hit a different element with the same id — exactly the
  /// ambiguity the selector already resolved.
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
    // One lookup serves both the focusing click and the typing.
    final elementId = await locateElement(element);
    if (elementId == null) {
      throw WebDriverException(
        'Could not locate element to type into '
        '(id=${element.resourceId}, text=${element.text})',
        error: webDriverNoSuchElement,
      );
    }
    await client.elementClick(sessionId, elementId);
    await typeInto(elementId, text, clear: clear);
  }

  @override
  Future<void> pressKey(NativeKey key) async => switch (key) {
        NativeKey.home => _pressButton('home'),
        NativeKey.volumeUp => _pressButton('volumeUp'),
        NativeKey.volumeDown => _pressButton('volumeDown'),
        NativeKey.enter => client.wdaKeys(sessionId, '\n'),
        NativeKey.backspace => client.wdaKeys(sessionId, '\b'),
        // The iOS software keyboard has no Tab key: `\t` would be typed
        // into the field as a character instead of moving focus.
        NativeKey.tab => throw const NativeUnsupportedException(
            'The iOS software keyboard has no Tab key.',
            hint: 'Tap the next field instead (native_tap or Flutter tap).',
          ),
        NativeKey.back => throw const NativeUnsupportedException(
            'iOS has no Back key.',
            // A short edge swipe (e.g. native_scroll's default 400 px) is
            // cancelled by iOS; the pop needs most of the screen width.
            hint: 'Tap the navigation bar back button (e.g. native_tap '
                'id="Back") or swipe right from the left screen edge across '
                'most of the screen (native_swipe startX=1, endX = about 70% '
                'of the screen width, startY = endY = mid-screen).',
          ),
        NativeKey.recents => throw const NativeUnsupportedException(
            'iOS has no recent-apps key.',
            hint: 'Use home to leave the app.',
          ),
      };

  /// Presses a hardware button; the Simulator only has `home`, and WDA's
  /// "not supported" answer is reported as such.
  Future<void> _pressButton(String name) async {
    try {
      await client.wdaPressButton(sessionId, name);
    } on WebDriverException catch (error) {
      if (!error.message.contains('not supported')) rethrow;
      throw NativeUnsupportedException(
        'The "$name" button is not available on this device.',
        hint: 'The iOS Simulator only has the home button; volume buttons '
            'exist on physical devices.',
      );
    }
  }

  @override
  Future<bool> isKeyboardShown() async =>
      wdaKeyboardOnScreen(await client.getPageSource(sessionId));

  @override
  Future<bool> hideKeyboard() async {
    if (!await isKeyboardShown()) return false;
    var dismissed = true;
    try {
      await client.wdaDismissKeyboard(sessionId, keyNames: _dismissKeyNames);
    } on WebDriverException {
      dismissed = await _tapAccessoryDone();
    }
    final closed = await pollUntil(
      () async => !await isKeyboardShown(),
      attempts: dismissed ? _keyboardCloseChecks : 1,
      interval: _keyboardCloseCheckInterval,
    );
    if (closed) return true;
    throw const NativeOperationFailedException(
      'Could not hide the iOS keyboard: it has no Done / dismiss key.',
      hint: 'Tap outside the field (native_tap on a non-interactive area), use '
          "the app's own Done button, or unfocus the field via the Flutter "
          'lane.',
    );
  }

  /// Taps the Done button of the bar above the keyboard (a WebView field's
  /// accessory bar), which WDA's dismiss does not look at. Returns false
  /// when there is none, so the caller confirms once instead of waiting
  /// for an animation that will not happen.
  Future<bool> _tapAccessoryDone() async {
    try {
      final done = await client.findElement(
        sessionId,
        'xpath',
        '//XCUIElementTypeToolbar//XCUIElementTypeButton[@name="Done"]',
      );
      await client.elementClick(sessionId, done);
      return true;
    } on WebDriverException {
      return false;
    }
  }

  /// Locates the WDA element for [element]: first by its type and exact
  /// geometry from the same UI tree (unique even when ids or labels repeat),
  /// then by accessibility id (`name`) or visible label/text; null when it
  /// is no longer on screen.
  ///
  /// A fallback that finds several elements throws instead of picking one:
  /// typing into the first could hit another field with the same label.
  Future<String?> locateElement(NativeElement element) async {
    try {
      return await client.findElement(
        sessionId,
        'xpath',
        wdaGeometryXPath(element, toServerUnits),
      );
    } on WebDriverException catch (exception) {
      if (isLostSession(exception)) rethrow;
      // Element moved or the tree changed; fall back to id/label below.
    }

    final id = element.resourceId;
    final text = element.text;
    final fallbacks = [
      if (id != null && id.isNotEmpty) ('accessibility id', id),
      if (text != null && text.isNotEmpty) ...[
        ('name', text),
        ('xpath', _wdaTextXPath(text)),
      ],
    ];

    for (final (using, value) in fallbacks) {
      switch (await client.findElements(sessionId, using, value)) {
        case [final only]:
          return only;
        case [_, _, ...] && final found:
          throw NativeOperationFailedException(
            '${found.length} elements match the field by $using, so the one '
            'to type into is unclear.',
            hint: 'Scroll the field fully into view, then retry. If it is '
                'already in view, native_tap it, then call native_enter_text '
                'without a selector.',
          );
      }
    }
    return null;
  }
}

/// XPath selecting the WDA element of [element]'s type at exactly its bounds,
/// converted to server units with [toServerUnits] (WDA reports integer
/// points, so the conversion back from screen pixels is exact).
String wdaGeometryXPath(
    NativeElement element, int Function(int) toServerUnits) {
  final bounds = element.bounds;
  final type = wdaType(element.className) == null ? '*' : element.className;
  return '//$type[@x=${toServerUnits(bounds.x)} and '
      '@y=${toServerUnits(bounds.y)} and '
      '@width=${toServerUnits(bounds.width)} and '
      '@height=${toServerUnits(bounds.height)}]';
}

/// XPath selecting every WDA element whose label, name or value is [text].
String _wdaTextXPath(String text) {
  final literal = xpathLiteral(text);
  return '//*[@label=$literal or @name=$literal or @value=$literal]';
}
