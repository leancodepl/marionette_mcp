import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';
import 'package:marionette_mcp/src/native_service/xpath.dart';

/// [NativeConnector] backed by WebDriverAgent on an iOS Simulator.
///
/// Use [connect] to bootstrap WDA (see [IosBootstrap]), open a WebDriver
/// session, and obtain a ready connector.
///
/// WebDriverAgent reports and accepts coordinates in points; this connector
/// converts them to screenshot pixels with the display scale read at
/// connect time (see docs/native-lane-decisions.md#d2).
final class IosNativeConnector extends WebDriverNativeConnector {
  IosNativeConnector._({
    required super.client,
    required super.sessionId,
    required super.bootstrap,
    required super.ownsBootstrap,
  });

  /// Screenshot pixels per point; read by [_loadScale] during [connect].
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
  }) async {
    final ownsBootstrap = bootstrap == null;
    final resolvedBootstrap = bootstrap ?? IosBootstrap(udid: udid);

    final connector = await WebDriverNativeConnector.openSession(
      bootstrap: resolvedBootstrap,
      ownsBootstrap: ownsBootstrap,
      capabilities: capabilities ?? const {'platformName': 'iOS'},
      create: (client, sessionId) => IosNativeConnector._(
        client: client,
        sessionId: sessionId,
        bootstrap: resolvedBootstrap,
        ownsBootstrap: ownsBootstrap,
      ),
    );
    try {
      await connector._loadScale();
    } catch (_) {
      await connector.dispose();
      rethrow;
    }
    return connector;
  }

  /// Reads the display scale from WDA's `wda/screen`; falls back to the
  /// screenshot width divided by the window width in points.
  Future<void> _loadScale() async {
    try {
      _scale = (await client.wdaScreen(sessionId)).scale;
      return;
    } on WebDriverException {
      // Older WDA builds: derive the scale from a screenshot below.
    }
    final window = await client.windowRectSize(sessionId);
    final png = pngSize(await client.takeScreenshot(sessionId));
    if (png == null || window.width <= 0) {
      throw const WebDriverException(
        'Could not determine the iOS display scale (wda/screen unavailable '
        'and the screenshot size is unknown)',
      );
    }
    _scale = png.width / window.width;
  }

  @override
  Future<NativeScreen> getScreen() async {
    ({int width, int height}) points;
    try {
      final screen = await client.wdaScreen(sessionId);
      points = (width: screen.width, height: screen.height);
    } on WebDriverException {
      points = await client.windowRectSize(sessionId);
    }
    return NativeScreen(
      width: (points.width * _scale).round(),
      height: (points.height * _scale).round(),
      scale: _scale,
    );
  }

  @override
  List<NativeElement> parseSource(String xml) => parseWdaSource(xml);

  @override
  String get classAttribute => 'type';

  static const _editableTypes = {
    'XCUIElementTypeTextField',
    'XCUIElementTypeSecureTextField',
    'XCUIElementTypeTextView',
    'XCUIElementTypeSearchField',
  };

  @override
  bool isEditableClass(String className) => _editableTypes.contains(className);

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
  /// ambiguity the selector already resolved (docs/native-lane-decisions.md#d1).
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
    final elementId = await _tryFindElement(element);
    if (elementId == null) {
      throw WebDriverException(
        'Could not locate element to type into '
        '(id=${element.resourceId}, text=${element.text})',
        error: 'no such element',
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
            hint: 'Tap the navigation bar back button (e.g. native_tap '
                'id="Back") or swipe right from the left screen edge '
                '(native_scroll direction=right startX=1 …).',
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
      (await client.getPageSource(sessionId))
          .contains('<XCUIElementTypeKeyboard');

  /// Keys that dismiss the keyboard without editing the text. `return` is
  /// deliberately absent: in a multi-line field it inserts a newline.
  static const _dismissKeyNames = ['Done', 'done', 'Hide keyboard', 'Dismiss'];

  @override
  Future<bool> hideKeyboard() async {
    if (!await isKeyboardShown()) return false;
    var dismissed = true;
    try {
      await client.wdaDismissKeyboard(sessionId, keyNames: _dismissKeyNames);
    } on WebDriverException {
      // WDA found no way to dismiss it; confirm once below instead of
      // waiting for an animation that will not happen.
      dismissed = false;
    }
    final attempts = dismissed ? 5 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!await isKeyboardShown()) return true;
      if (attempt < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw const NativeOperationFailedException(
      'Could not hide the iOS keyboard: it has no Done / dismiss key.',
      hint: 'Tap outside the field (native_tap on a non-interactive area), use '
          "the app's own Done button, or unfocus the field via the Flutter "
          'lane.',
    );
  }

  /// Locates the WDA element for [element]: first by its type and exact
  /// geometry from the same UI tree (unique even when ids or labels repeat),
  /// then by accessibility id (`name`) or visible label/text.
  Future<String?> _tryFindElement(NativeElement element) async {
    try {
      return await client.findElement(
        sessionId,
        'xpath',
        wdaGeometryXPath(element, toServerUnits),
      );
    } on WebDriverException {
      // Element moved or the tree changed; fall back to id/label below.
    }

    final id = element.resourceId;
    if (id != null && id.isNotEmpty) {
      try {
        return await client.findElement(sessionId, 'accessibility id', id);
      } on WebDriverException {
        // Fall through to name/label strategies.
      }
    }

    final text = element.text;
    if (text != null && text.isNotEmpty) {
      try {
        return await client.findElement(sessionId, 'name', text);
      } on WebDriverException {
        // Fall through.
      }
      try {
        final literal = xpathLiteral(text);
        return await client.findElement(
          sessionId,
          'xpath',
          '//*[@label=$literal or @name=$literal or @value=$literal]',
        );
      } on WebDriverException {
        return null;
      }
    }

    return null;
  }
}

/// Reads a bundle identifier from WDA page source when [wdaActiveAppInfo] is
/// unavailable.
String? foregroundAppFromWdaSource(String xml) {
  final apps = parseUiTree(
    xml,
    isRelevant: (attributes) =>
        attributes[uiNodeTagKey] == 'XCUIElementTypeApplication',
  );
  if (apps.isEmpty) return null;

  final attrs = apps.first;
  final bundleId = attrs['bundleId'] ?? '';
  if (bundleId.isNotEmpty) return bundleId;

  final name = attrs['name'] ?? '';
  if (_looksLikeBundleIdentifier(name)) return name;

  return null;
}

final _bundleIdentifierPattern = RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$');

bool _looksLikeBundleIdentifier(String value) =>
    _bundleIdentifierPattern.hasMatch(value);

/// XPath selecting the WDA element of [element]'s type at exactly its bounds,
/// converted to server units with [toServerUnits] (WDA reports integer
/// points, so the conversion back from screenshot pixels is exact).
String wdaGeometryXPath(
    NativeElement element, int Function(int) toServerUnits) {
  final bounds = element.bounds;
  final type =
      element.className.startsWith('XCUIElementType') ? element.className : '*';
  return '//$type[@x=${toServerUnits(bounds.x)} and '
      '@y=${toServerUnits(bounds.y)} and '
      '@width=${toServerUnits(bounds.width)} and '
      '@height=${toServerUnits(bounds.height)}]';
}
