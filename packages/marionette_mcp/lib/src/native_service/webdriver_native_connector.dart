import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// Shared implementation of [NativeConnector] for WebDriver-based servers
/// (UIAutomator2 on Android, WebDriverAgent on iOS).
///
/// Owns the [WebDriverClient], the session and — when [ownsBootstrap] — the
/// server bootstrap. Platform subclasses supply the session capabilities
/// (via [openSession]), [parseSource], [getScreen], and the operations whose
/// protocol differs per platform ([tapElement], [enterText],
/// [foregroundApp]).
///
/// Coordinates crossing this class are screenshot pixels; the server may
/// work in other units. [serverUnitScale] converts between the two: element
/// bounds from the server are multiplied by it, coordinates sent to the
/// server divided by it.
abstract base class WebDriverNativeConnector implements NativeConnector {
  WebDriverNativeConnector({
    required this.client,
    required this.sessionId,
    required NativeServerBootstrap bootstrap,
    required bool ownsBootstrap,
  })  : _bootstrap = bootstrap,
        _ownsBootstrap = ownsBootstrap;

  /// Client for the session's server; for use by subclasses.
  final WebDriverClient client;

  /// Id of the WebDriver session this connector drives.
  final String sessionId;

  final NativeServerBootstrap _bootstrap;

  /// Whether [dispose] disposes the bootstrap.
  final bool _ownsBootstrap;
  bool _disposed = false;

  /// Whether [dispose] deletes the session. A subclass turns it off when
  /// deleting would stop a server another process owns.
  bool get deletesSessionOnDispose => true;

  /// Starts the server through [bootstrap], opens a session with
  /// [capabilities] and hands both to [create].
  ///
  /// With [sessionId], that session is reused while the server still has it
  /// (the CLI keeps one session across its commands); otherwise a new one
  /// is opened.
  ///
  /// When opening the session fails, the client is closed and — if
  /// [ownsBootstrap] — the bootstrap disposed before the error propagates.
  /// A failing `ensureServerReady` cleans up after itself.
  static Future<C> openSession<C extends WebDriverNativeConnector>({
    required NativeServerBootstrap bootstrap,
    required bool ownsBootstrap,
    required Map<String, dynamic> capabilities,
    required C Function(WebDriverClient client, String sessionId) create,
    String? sessionId,
  }) async {
    final baseUri = await bootstrap.ensureServerReady();
    final client = WebDriverClient(baseUri.toString());
    try {
      final id = sessionId != null && await _sessionAlive(client, sessionId)
          ? sessionId
          : await client.createSession(capabilities: capabilities);
      return create(client, id);
    } catch (_) {
      client.close();
      if (ownsBootstrap) await bootstrap.dispose();
      rethrow;
    }
  }

  /// Whether the server still has session [sessionId] — read through a
  /// cheap call both servers support.
  static Future<bool> _sessionAlive(
    WebDriverClient client,
    String sessionId,
  ) async {
    try {
      await client.getOrientation(sessionId);
      return true;
    } on WebDriverException {
      return false;
    }
  }

  /// Converts the server's page source into [NativeElement]s, with bounds
  /// in server units.
  List<NativeElement> parseSource(String xml);

  /// Screenshot pixels per server unit: 1 when the server works in pixels.
  double get serverUnitScale => 1;

  /// Converts a coordinate in screenshot pixels to server units.
  int toServerUnits(int pixels) =>
      serverUnitScale == 1 ? pixels : (pixels / serverUnitScale).round();

  @override
  Future<List<NativeElement>> getNativeElements() async {
    final elements = parseSource(await client.getPageSource(sessionId));
    final scale = serverUnitScale;
    return scale == 1
        ? elements
        : [for (final element in elements) element.scaled(scale)];
  }

  @override
  Future<void> tapAt(int x, int y) {
    final serverX = toServerUnits(x);
    final serverY = toServerUnits(y);
    // A zero-length swipe is a tap in both servers' W3C actions support.
    return client.swipe(
      sessionId,
      startX: serverX,
      startY: serverY,
      endX: serverX,
      endY: serverY,
      durationMs: 50,
    );
  }

  @override
  Future<void> swipe({
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
    int holdMs = 0,
  }) {
    return client.swipe(
      sessionId,
      startX: toServerUnits(startX),
      startY: toServerUnits(startY),
      endX: toServerUnits(endX),
      endY: toServerUnits(endY),
      durationMs: durationMs,
      holdMs: holdMs,
    );
  }

  @override
  Future<String> takeScreenshot() => client.takeScreenshot(sessionId);

  /// Name of the element attribute holding its class (`className` on
  /// UIAutomator2, `type` on WebDriverAgent).
  String get classAttribute;

  /// Whether an element of [className] accepts typed text.
  bool isEditableClass(String className);

  static const _focusHint = 'Focus a text field first (native_tap on it, or '
      'Flutter tap for a Flutter TextField), or pass a selector for the '
      'field.';

  /// Types into the focused field: W3C `element/active`, then send keys.
  ///
  /// The focused element must be a text field: after e.g. a Tab press the
  /// focus may sit on a button, and send keys would then fail or — on
  /// UIAutomator2 — report success without typing anything.
  @override
  Future<void> typeText(String text, {bool clear = false}) async {
    final String elementId;
    try {
      elementId = await client.activeElement(sessionId);
    } on WebDriverException catch (error) {
      if (!isNoSuchElement(error)) rethrow;
      throw NativeElementNotFoundException('keyboard focus', hint: _focusHint);
    }

    final className = await _classOf(elementId);
    if (className != null && !isEditableClass(className)) {
      throw NativeElementNotFoundException(
        'keyboard focus on a text field (focus is on $className)',
        hint: _focusHint,
      );
    }
    await typeInto(elementId, text, clear: clear);
  }

  /// Class of [elementId], or null when the server cannot report it — then
  /// typing proceeds unchecked rather than blocking unusual fields.
  Future<String?> _classOf(String elementId) async {
    try {
      final value =
          await client.elementAttribute(sessionId, elementId, classAttribute);
      return value == null || value.isEmpty ? null : value;
    } on WebDriverException {
      return null;
    }
  }

  /// Types [text] into the WebDriver element [elementId], clearing it first
  /// when [clear] is set.
  Future<void> typeInto(
    String elementId,
    String text, {
    required bool clear,
  }) async {
    if (clear) await client.elementClear(sessionId, elementId);
    if (text.isNotEmpty) {
      await client.elementSendKeys(sessionId, elementId, text);
    }
  }

  /// Whether [error] means "no matching element" on either server.
  static bool isNoSuchElement(WebDriverException error) =>
      error.error == 'no such element' || error.httpStatus == 404;

  /// Closes the client but keeps the session and the server, for a later
  /// process to reuse them through `openSession(sessionId: …)` — the CLI.
  /// Afterwards [dispose] does nothing.
  void release() {
    if (_disposed) return;
    _disposed = true;
    client.close();
  }

  /// Deletes the session (see [deletesSessionOnDispose]), closes the client
  /// and — when owned — disposes the bootstrap. Idempotent.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (deletesSessionOnDispose) await client.deleteSession(sessionId);
    } catch (_) {
      // Continue teardown when the server/session has already disappeared.
    } finally {
      client.close();
      if (_ownsBootstrap) await _bootstrap.dispose();
    }
  }
}
