import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
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
  Future<void> enterText(NativeElement element, String text) async {
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
    await client.elementSendKeys(sessionId, elementId, text);
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
