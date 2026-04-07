import 'dart:async';
import 'dart:js_interop';
import 'dart:ui';

import 'package:web/web.dart' as web;

import 'package:marionette_flutter/src/services/frame_protocol.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';
import 'package:marionette_flutter/src/services/screencast_service.dart';

/// Manages screencast lifecycle with a WebSocket push channel for web apps.
///
/// Unlike the TCP server implementation (which binds a TCP server), this connects
/// as a WebSocket *client* to a server hosted by the MCP/CLI side. The MCP
/// side provides the WebSocket port via the `wsPort` extension parameter.
///
/// Frame data is pushed as binary WebSocket messages using the same MRNT
/// protocol (20-byte header + raw RGBA payload).
class ScreencastWebServer implements ScreencastServer {
  ScreencastWebServer({
    required ScreencastServiceFactory screencastServiceFactory,
    required ViewportSizeProvider viewportSizeProvider,
  })  : _screencastServiceFactory = screencastServiceFactory,
        _viewportSizeProvider = viewportSizeProvider;

  final ScreencastServiceFactory _screencastServiceFactory;
  final ViewportSizeProvider _viewportSizeProvider;

  ScreencastService? _service;
  web.WebSocket? _webSocket;
  bool _isActive = false;
  bool _isStopping = false;

  @override
  bool get isActive => _isActive;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    if (_isActive || _isStopping) {
      throw StateError('Screencast already active');
    }

    final size = _viewportSizeProvider();
    final nativeW = size.width.round();
    final nativeH = size.height.round();

    final maxSize = (maxWidth != null && maxHeight != null)
        ? Size(maxWidth.toDouble(), maxHeight.toDouble())
        : null;
    final (frameW, frameH) =
        ScreencastService.computeFrameSize(nativeW, nativeH, maxSize);

    // No wsPort yet — the CLI is probing to discover the transport type.
    // Return viewport info so it can compute video dimensions, then it will
    // call again with wsPort to actually start the screencast.
    if (wsPort == null) {
      return {
        'message': 'Screencast requires wsPort',
        'transport': 'ws',
        'viewportWidth': nativeW,
        'viewportHeight': nativeH,
        'frameWidth': frameW,
        'frameHeight': frameH,
      };
    }

    _service = _screencastServiceFactory(maxSize: maxSize);
    _isActive = true;

    // Connect to the MCP-hosted WebSocket server.
    final completer = Completer<void>();
    _webSocket = web.WebSocket('ws://localhost:$wsPort');
    _webSocket!.binaryType = 'arraybuffer';

    // Use listen() (not .first) for the connect-phase error handler so we can
    // cancel it explicitly when onOpen fires and prevent a zombie subscription
    // from outliving the connection-setup phase.  If an error event fires
    // after onOpen (e.g. mid-session), only the lifecycle handler registered
    // below (after the guard) would fire — not this stale connect-time one.
    StreamSubscription<web.Event>? connectErrorSub;
    connectErrorSub = _webSocket!.onError.listen((_) {
      connectErrorSub?.cancel();
      connectErrorSub = null;
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Failed to connect WebSocket to localhost:$wsPort'),
        );
      }
    });
    _webSocket!.onOpen.first.then((_) {
      connectErrorSub?.cancel(); // Kill zombie before lifecycle handlers go up.
      connectErrorSub = null;
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await completer.future;
    } catch (_) {
      connectErrorSub?.cancel();
      connectErrorSub = null;
      _isActive = false;
      _service = null;
      _webSocket = null;
      rethrow;
    }

    // Guard against stopScreencast() being called concurrently while the
    // WebSocket was connecting (e.g., a hot reload triggering
    // reassembleApplication).
    //
    // Two cases to catch:
    //  • _service == null : stopScreencast() already finished and nulled it.
    //  • _isStopping     : stopScreencast() is mid-execution (awaiting GPU
    //    capture in _service.stop()) — the service is not yet nulled but will
    //    be; we must not start it.
    if (_service == null || _isStopping) {
      _isActive = false;
      _webSocket?.close();
      _webSocket = null;
      throw StateError(
        'Screencast was stopped while the WebSocket connection was being '
        'established (e.g., hot reload during start)',
      );
    }

    // Stop capturing if the WebSocket disconnects unexpectedly.
    _webSocket!.onClose.first.then((_) => stopScreencast());
    _webSocket!.onError.first.then((_) => stopScreencast());

    _service!.start(onFrame: _onFrame);

    return {
      'message': 'Screencast started',
      'transport': 'ws',
      'viewportWidth': nativeW,
      'viewportHeight': nativeH,
      'frameWidth': frameW,
      'frameHeight': frameH,
    };
  }

  @override
  Future<void> stopScreencast() async {
    // Guard against re-entrant calls (e.g. an onClose / onError handler fires
    // while a hot-reload-triggered stopScreencast is still awaiting
    // _service.stop(), which itself awaits an in-flight GPU capture).
    if (_isStopping) return;
    if (!_isActive) return;
    _isStopping = true;
    try {
      await _service?.stop();
      _service = null;
      _isActive = false;
      _webSocket?.close();
      _webSocket = null;
    } finally {
      _isStopping = false;
    }
  }

  Future<void> _onFrame(ScreencastFrame frame) async {
    final ws = _webSocket;
    if (ws == null || ws.readyState != web.WebSocket.OPEN) return;

    final header = FrameHeader(
      frameLength: frame.rgbaBytes.length,
      width: frame.width,
      height: frame.height,
      timestampMs: frame.timestampMs,
    );
    final message = header.encodeWithPayload(frame.rgbaBytes);

    ws.send(message.buffer.toJS);
  }
}
