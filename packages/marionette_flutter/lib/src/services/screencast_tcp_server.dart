import 'dart:io';
import 'dart:ui';

import 'package:marionette_flutter/src/services/frame_protocol.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';
import 'package:marionette_flutter/src/services/screencast_service.dart';

/// Manages screencast lifecycle with a TCP push channel for frame delivery.
///
/// On [startScreencast], binds a TCP server on localhost and starts capturing
/// frames. Each frame is pushed to connected clients as a binary message
/// (20-byte MRNT header + raw RGBA payload). This eliminates the VM service
/// polling overhead that limited the old architecture to ~1.4 FPS.
class ScreencastTcpServer implements ScreencastServer {
  ScreencastTcpServer({
    required ScreencastServiceFactory screencastServiceFactory,
    required ViewportSizeProvider viewportSizeProvider,
  })  : _screencastServiceFactory = screencastServiceFactory,
        _viewportSizeProvider = viewportSizeProvider;

  final ScreencastServiceFactory _screencastServiceFactory;
  final ViewportSizeProvider _viewportSizeProvider;

  ScreencastService? _service;
  ServerSocket? _serverSocket;
  final List<Socket> _clients = [];
  bool _isActive = false;

  @override
  bool get isActive => _isActive;

  /// The TCP port clients should connect to, or null if not active.
  int? get port => _serverSocket?.port;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    if (_isActive) {
      throw StateError('Screencast already active');
    }

    final maxSize = (maxWidth != null && maxHeight != null)
        ? Size(maxWidth.toDouble(), maxHeight.toDouble())
        : null;

    _service = _screencastServiceFactory(maxSize: maxSize);
    _isActive = true;

    // Bind TCP server on localhost with an OS-assigned port.
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _serverSocket!.listen(_onClientConnected);

    _service!.start(onFrame: _onFrame);

    final size = _viewportSizeProvider();
    final nativeW = size.width.round();
    final nativeH = size.height.round();
    final (frameW, frameH) =
        ScreencastService.computeFrameSize(nativeW, nativeH, maxSize);
    return {
      'message': 'Screencast started',
      'transport': 'tcp',
      'viewportWidth': nativeW,
      'viewportHeight': nativeH,
      'frameWidth': frameW,
      'frameHeight': frameH,
      'port': _serverSocket!.port,
    };
  }

  @override
  Future<void> stopScreencast() async {
    if (_isActive) {
      await _service?.stop();
      _service = null;
      _isActive = false;
      final clients = List<Socket>.of(_clients);
      _clients.clear();
      for (final client in clients) {
        try {
          await client.close();
          client.destroy();
        } catch (_) {}
      }
      await _serverSocket?.close();
      _serverSocket = null;
    }
  }

  void _onClientConnected(Socket client) {
    _clients.add(client);
    client.done.whenComplete(() => _clients.remove(client));
  }

  Future<void> _onFrame(ScreencastFrame frame) async {
    if (_clients.isEmpty) return;

    final header = FrameHeader(
      frameLength: frame.rgbaBytes.length,
      width: frame.width,
      height: frame.height,
      timestampMs: frame.timestampMs,
    );
    final message = header.encodeWithPayload(frame.rgbaBytes);

    // Snapshot the list so concurrent connect/disconnect events cannot
    // modify it mid-iteration (defensive — safe today because the loop
    // is synchronous, but protects against future changes).

    final clients = List<Socket>.of(_clients);
    final disconnected = <Socket>[];
    for (final client in clients) {
      try {
        client.add(message);
      } catch (_) {
        disconnected.add(client);
      }
    }
    for (final client in disconnected) {
      _clients.remove(client);
      try {
        client.destroy();
      } catch (_) {}
    }
  }
}
