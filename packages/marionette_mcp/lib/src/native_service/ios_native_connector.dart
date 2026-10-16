import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';
import 'package:marionette_mcp/src/native_service/xpath.dart';

/// [NativeConnector] backed by WebDriverAgent on an iOS Simulator.
///
/// Use [connect] to bootstrap WDA (see [IosBootstrap]), open a WebDriver
/// session, and obtain a ready connector. Coordinates are physical pixels.
final class IosNativeConnector extends WebDriverNativeConnector {
  IosNativeConnector._({
    required super.client,
    required super.sessionId,
    required super.bootstrap,
    required super.ownsBootstrap,
  });

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
  }) {
    final ownsBootstrap = bootstrap == null;
    final resolvedBootstrap = bootstrap ?? IosBootstrap(udid: udid);

    return WebDriverNativeConnector.openSession(
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

  @override
  Future<void> tapElement(NativeElement element) async {
    final elementId = await _tryFindElement(element);
    if (elementId != null) {
      await client.elementClick(sessionId, elementId);
      return;
    }
    final center = element.center;
    await tapAt(center.x, center.y);
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

  /// Locates the element by accessibility id (`name`) or visible label/text.
  Future<String?> _tryFindElement(NativeElement element) async {
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
