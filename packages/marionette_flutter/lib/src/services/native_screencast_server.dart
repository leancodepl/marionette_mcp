import 'package:marionette_flutter/src/services/screencast_native_ws_client.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';
import 'package:marionette_flutter/src/services/screencast_tcp_server.dart';

/// Dispatcher that selects the appropriate native screencast transport.
///
/// When [startScreencast] is called without a [wsPort], it delegates to a
/// [ScreencastTcpServer] (TCP push channel). When called with a [wsPort], it
/// delegates to a [ScreencastNativeWsClient] (reverse WebSocket channel).
///
/// This allows the same factory wiring to serve both the probe phase (TCP,
/// no wsPort) and the live recording phase (WS, with wsPort).
class NativeScreencastServer implements ScreencastServer {
  NativeScreencastServer({
    required ScreencastServiceFactory screencastServiceFactory,
    required ViewportSizeProvider viewportSizeProvider,
  })  : _screencastServiceFactory = screencastServiceFactory,
        _viewportSizeProvider = viewportSizeProvider;

  final ScreencastServiceFactory _screencastServiceFactory;
  final ViewportSizeProvider _viewportSizeProvider;

  ScreencastServer? _activeDelegate;

  @override
  bool get isActive => _activeDelegate?.isActive ?? false;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    if (_activeDelegate != null) {
      throw StateError('Screencast already active');
    }

    if (wsPort != null) {
      _activeDelegate = ScreencastNativeWsClient(
        screencastServiceFactory: _screencastServiceFactory,
        viewportSizeProvider: _viewportSizeProvider,
      );
    } else {
      _activeDelegate = ScreencastTcpServer(
        screencastServiceFactory: _screencastServiceFactory,
        viewportSizeProvider: _viewportSizeProvider,
      );
    }

    try {
      return await _activeDelegate!.startScreencast(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        wsPort: wsPort,
      );
    } catch (_) {
      _activeDelegate = null;
      rethrow;
    }
  }

  @override
  Future<void> stopScreencast() async {
    await _activeDelegate?.stopScreencast();
    _activeDelegate = null;
  }
}
