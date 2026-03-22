import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:marionette_flutter/src/services/frame_protocol.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';
import 'package:marionette_flutter/src/services/screencast_service.dart';

/// Manages screencast lifecycle with a WebSocket push channel for native apps.
///
/// Unlike the TCP server implementation (which binds a TCP server), this
/// connects as a WebSocket *client* to a server hosted by the MCP/CLI side.
/// The MCP side provides the WebSocket port via the `wsPort` parameter.
///
/// Frame data is pushed as binary WebSocket messages using the same MRNT
/// protocol (20-byte header + raw RGBA payload).
///
/// Uses [dart:io] [WebSocket.connect] — not available on web. For web use
/// [ScreencastWebServer] instead.
class ScreencastNativeWsClient implements ScreencastServer {
  ScreencastNativeWsClient({
    required ScreencastServiceFactory screencastServiceFactory,
    required ViewportSizeProvider viewportSizeProvider,
  })  : _screencastServiceFactory = screencastServiceFactory,
        _viewportSizeProvider = viewportSizeProvider;

  final ScreencastServiceFactory _screencastServiceFactory;
  final ViewportSizeProvider _viewportSizeProvider;

  ScreencastService? _service;
  WebSocket? _webSocket;
  bool _isActive = false;

  @override
  bool get isActive => _isActive;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    if (wsPort == null) {
      throw ArgumentError.notNull('wsPort');
    }

    if (_isActive) {
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

    // Connect to the MCP-hosted WebSocket server with a 5-second timeout.
    final ws = await WebSocket.connect('ws://localhost:$wsPort')
        .timeout(const Duration(seconds: 5));

    _webSocket = ws;
    _service = _screencastServiceFactory(maxSize: maxSize);
    _isActive = true;

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
    if (_isActive) {
      await _service?.stop();
      _service = null;
      _isActive = false;
      await _webSocket?.close();
      _webSocket = null;
    }
  }

  Future<void> _onFrame(ScreencastFrame frame) async {
    final ws = _webSocket;
    if (ws == null || ws.closeCode != null) return;

    final header = FrameHeader(
      frameLength: frame.rgbaBytes.length,
      width: frame.width,
      height: frame.height,
      timestampMs: frame.timestampMs,
    );

    ws.add(header.encodeWithPayload(frame.rgbaBytes));
  }
}
