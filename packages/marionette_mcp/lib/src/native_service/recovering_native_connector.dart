import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// Creates a fresh connector for the same target as the one being replaced.
typedef NativeReconnect = Future<NativeConnector> Function();

/// [NativeConnector] decorator that re-establishes a lost device-side
/// session (see docs/native-lane-decisions.md#d3).
///
/// Every operation is classified by its method:
/// - reads ([getNativeElements], [foregroundApp], [takeScreenshot],
///   [takeElementScreenshot], [getScreen], [getOrientation],
///   [isKeyboardShown]) are
///   retried once on a fresh session whenever the session was lost;
/// - actions ([tapElement], [tapAt], [enterText], [typeText], [pressKey],
///   [hideKeyboard], [swipe], [longPress], [doubleTap], [pinch],
///   [setOrientation]) first check
///   [isServerResponding]; a server that is already gone is replaced before
///   the action is sent. An action is retried only when it certainly did
///   not run — the server answered `invalid session id`, or no connection
///   could be opened so nothing was sent. If the connection broke after the
///   request was sent, the action may have run: it is not repeated,
///   [NativeSessionLostException] is thrown, and the session is
///   re-established at the start of the next call.
///
/// A second loss right after re-establishing, or a failed re-establish,
/// closes this connector: later calls throw [NativeNotConnectedException]
/// and [onClosed] is invoked.
final class RecoveringNativeConnector implements NativeConnector {
  RecoveringNativeConnector(
    NativeConnector initial, {
    required NativeReconnect reconnect,
    required logging.Logger logger,
    void Function()? onClosed,
  })  : _inner = initial,
        _reconnect = reconnect,
        _logger = logger,
        _onClosed = onClosed;

  final NativeReconnect _reconnect;
  final logging.Logger _logger;
  final void Function()? _onClosed;

  /// The connector currently in use; null once closed.
  NativeConnector? _inner;

  /// Set when an action was interrupted; the next call reconnects first.
  bool _reconnectPending = false;

  /// In-flight re-establish shared by concurrent callers.
  Future<NativeConnector>? _reconnecting;

  /// Set by [dispose]: an operation still running then (e.g. a read that a
  /// tool stopped waiting for) fails with the closed connection, and that
  /// must not start a new session (docs/native-lane-decisions.md#d3).
  bool _disposed = false;

  @override
  Future<List<NativeElement>> getNativeElements() =>
      _read((c) => c.getNativeElements());

  @override
  Future<String?> get foregroundApp => _read((c) => c.foregroundApp);

  @override
  Future<String> takeScreenshot() => _read((c) => c.takeScreenshot());

  @override
  Future<NativeScreen> getScreen() => _read((c) => c.getScreen());

  @override
  Future<void> tapElement(NativeElement element) =>
      _act((c) => c.tapElement(element));

  @override
  Future<void> tapAt(int x, int y) => _act((c) => c.tapAt(x, y));

  @override
  Future<void> enterText(
    NativeElement element,
    String text, {
    bool clear = false,
  }) =>
      _act((c) => c.enterText(element, text, clear: clear));

  @override
  Future<void> typeText(String text, {bool clear = false}) =>
      _act((c) => c.typeText(text, clear: clear));

  @override
  Future<void> pressKey(NativeKey key) => _act((c) => c.pressKey(key));

  @override
  Future<bool> hideKeyboard() => _act((c) => c.hideKeyboard());

  @override
  Future<bool> isKeyboardShown() => _read((c) => c.isKeyboardShown());

  @override
  Future<void> swipe({
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
    int holdMs = 0,
  }) =>
      _act(
        (c) => c.swipe(
          startX: startX,
          startY: startY,
          endX: endX,
          endY: endY,
          durationMs: durationMs,
          holdMs: holdMs,
        ),
      );

  @override
  Future<void> longPress(int x, int y, {int durationMs = 600}) =>
      _act((c) => c.longPress(x, y, durationMs: durationMs));

  @override
  Future<void> doubleTap(int x, int y, {int delayMs = 100}) =>
      _act((c) => c.doubleTap(x, y, delayMs: delayMs));

  @override
  Future<void> pinch({
    required int centerX,
    required int centerY,
    required int startSpan,
    required int endSpan,
    int durationMs = 500,
  }) =>
      _act(
        (c) => c.pinch(
          centerX: centerX,
          centerY: centerY,
          startSpan: startSpan,
          endSpan: endSpan,
          durationMs: durationMs,
        ),
      );

  @override
  Future<String> takeElementScreenshot(NativeElement element) =>
      _read((c) => c.takeElementScreenshot(element));

  @override
  Future<NativeOrientation> getOrientation() =>
      _read((c) => c.getOrientation());

  @override
  Future<void> setOrientation(NativeOrientation orientation) =>
      _act((c) => c.setOrientation(orientation));

  /// Device of the current connector. Device operations do not use the
  /// WebDriver session, so they need no recovery.
  @override
  NativeDevice get device =>
      (_inner ?? (throw const NativeNotConnectedException())).device;

  /// Health probe of the current connector; never triggers recovery.
  @override
  Future<bool> isServerResponding() async =>
      await _inner?.isServerResponding() ?? false;

  /// Recovery is this decorator's job; it does not reopen on request.
  @override
  Future<NativeConnector?> reopenSession() async => null;

  @override
  Future<void> dispose() async {
    _disposed = true;
    final inner = _inner;
    _inner = null;
    _reconnectPending = false;
    await inner?.dispose();
  }

  Future<T> _read<T>(Future<T> Function(NativeConnector c) operation) =>
      _run(operation, isRead: true);

  Future<T> _act<T>(Future<T> Function(NativeConnector c) operation) =>
      _run(operation, isRead: false);

  Future<T> _run<T>(
    Future<T> Function(NativeConnector c) operation, {
    required bool isRead,
  }) async {
    var inner = await _ready();
    if (!isRead && !await inner.isServerResponding()) {
      // Behind `adb forward` a dead server only shows up after a request is
      // sent, which would make the action's outcome unknown. Checking first
      // lets us replace a server that was already gone and act safely.
      _logger.info('Native server not responding before an action; '
          're-establishing the session first');
      inner = await _replace(inner);
    }
    try {
      return await operation(inner);
    } on WebDriverException catch (error) {
      final loss = _sessionLossOf(error);
      if (loss == null) rethrow;
      if (_disposed) throw const NativeNotConnectedException();

      if (!isRead && loss == _SessionLoss.connectionLost) {
        _reconnectPending = true;
        throw NativeSessionLostException(
          'Lost the native session while performing an action; the action '
          'may or may not have been performed. ($error)',
          hint: 'Call native_get_elements to check the current state. The '
              'session is re-established automatically on the next call.',
        );
      }

      _logger.info('Native session lost ($error); re-establishing it once');
      // `invalid session id`: the server answered, only the session is gone
      // (e.g. another client took UIAutomator2's single session) — open a
      // new one there instead of restarting the server.
      inner = await _replace(
        inner,
        reopen: loss == _SessionLoss.invalidSession,
      );
      try {
        return await operation(inner);
      } on WebDriverException catch (retryError) {
        if (_sessionLossOf(retryError) == null) rethrow;
        await _close();
        throw NativeSessionLostException(
          'The native session was lost again right after re-establishing it. '
          '($retryError)',
          hint: 'Check the device or simulator and call native_connect again.',
        );
      }
    }
  }

  Future<NativeConnector> _ready() async {
    if (_disposed) throw const NativeNotConnectedException();
    final inner = _inner;
    if (_reconnectPending) return _replace(inner);
    final reconnecting = _reconnecting;
    if (reconnecting != null) return reconnecting;
    if (inner == null) throw const NativeNotConnectedException();
    return inner;
  }

  /// Replaces [broken] with a fresh connector, unless a concurrent call
  /// already did (or is doing) so. With [reopen], a new session on the same
  /// server is tried first.
  Future<NativeConnector> _replace(
    NativeConnector? broken, {
    bool reopen = false,
  }) {
    final reconnecting = _reconnecting;
    if (reconnecting != null) return reconnecting;
    final current = _inner;
    if (current != null && !identical(current, broken) && !_reconnectPending) {
      return Future.value(current);
    }
    return _reconnecting = _doReplace(broken, reopen: reopen).whenComplete(() {
      _reconnecting = null;
    });
  }

  Future<NativeConnector> _doReplace(
    NativeConnector? broken, {
    required bool reopen,
  }) async {
    _reconnectPending = false;
    _inner = null;
    if (reopen && broken != null) {
      NativeConnector? reopened;
      try {
        reopened = await broken.reopenSession();
      } catch (error) {
        _logger.info('Could not open a new session on the same server '
            '($error); restarting it');
      }
      if (reopened != null) {
        try {
          // Its server moved to [reopened]; only the lost session remains.
          await broken.dispose();
        } catch (_) {
          // Best-effort, as below.
        }
        _inner = reopened;
        return reopened;
      }
    }
    if (broken != null) {
      try {
        await broken.dispose();
      } catch (_) {
        // The old session is already broken; teardown is best-effort.
      }
    }

    try {
      final fresh = await _reconnect();
      _inner = fresh;
      return fresh;
    } catch (error) {
      await _close();
      throw NativeSessionLostException(
        'The native session was lost and could not be re-established: $error',
        hint: 'Check the device or simulator and call native_connect again.',
      );
    }
  }

  Future<void> _close() async {
    await dispose();
    _onClosed?.call();
  }

  static _SessionLoss? _sessionLossOf(WebDriverException error) =>
      switch (error.error) {
        webDriverInvalidSessionId => _SessionLoss.invalidSession,
        webDriverServerUnreachable => _SessionLoss.serverUnreachable,
        webDriverConnectionLost => _SessionLoss.connectionLost,
        _ => null,
      };
}

/// How a session was lost; only [connectionLost] leaves it unknown whether
/// the last request was executed.
enum _SessionLoss { invalidSession, serverUnreachable, connectionLost }
