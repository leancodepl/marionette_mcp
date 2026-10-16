import 'package:marionette_mcp/src/native_service/native_connector.dart';
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
/// server divided by it (see docs/native-lane-decisions.md#d2).
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
  final bool _ownsBootstrap;
  bool _disposed = false;

  /// Starts the server through [bootstrap], opens a session with
  /// [capabilities] and hands both to [create].
  ///
  /// When opening the session fails, the client is closed and — if
  /// [ownsBootstrap] — the bootstrap disposed before the error propagates.
  /// A failing `ensureServerReady` cleans up after itself.
  static Future<C> openSession<C extends WebDriverNativeConnector>({
    required NativeServerBootstrap bootstrap,
    required bool ownsBootstrap,
    required Map<String, dynamic> capabilities,
    required C Function(WebDriverClient client, String sessionId) create,
  }) async {
    final baseUri = await bootstrap.ensureServerReady();
    final client = WebDriverClient(baseUri.toString());
    try {
      final sessionId = await client.createSession(capabilities: capabilities);
      return create(client, sessionId);
    } catch (_) {
      client.close();
      if (ownsBootstrap) await bootstrap.dispose();
      rethrow;
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
  }) {
    return client.swipe(
      sessionId,
      startX: toServerUnits(startX),
      startY: toServerUnits(startY),
      endX: toServerUnits(endX),
      endY: toServerUnits(endY),
      durationMs: durationMs,
    );
  }

  @override
  Future<String> takeScreenshot() => client.takeScreenshot(sessionId);

  /// How long [isServerResponding] waits before treating the server as
  /// gone. Generous, because WebDriverAgent can be slow while busy and a
  /// false negative costs a full reconnect.
  static const serverResponseTimeout = Duration(seconds: 5);

  @override
  Future<bool> isServerResponding() =>
      client.status().timeout(serverResponseTimeout, onTimeout: () => false);

  /// Deletes the session, closes the client and — when owned — disposes the
  /// bootstrap. Idempotent.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await client.deleteSession(sessionId);
    } catch (_) {
      // Continue teardown when the server/session has already disappeared.
    } finally {
      client.close();
      if (_ownsBootstrap) await _bootstrap.dispose();
    }
  }
}
