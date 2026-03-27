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

  @override
  bool get isActive => _isActive;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
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

    _webSocket!.onOpen.first.then((_) {
      if (!completer.isCompleted) completer.complete();
    });
    _webSocket!.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Failed to connect WebSocket to localhost:$wsPort'),
        );
      }
    });

    try {
      await completer.future;
    } catch (_) {
      _isActive = false;
      _service = null;
      _webSocket = null;
      rethrow;
    }

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
      _webSocket?.close();
      _webSocket = null;
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
