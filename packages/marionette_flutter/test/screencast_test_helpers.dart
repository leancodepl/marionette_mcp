import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_flutter/src/services/screencast_service.dart';

/// A fake ScreencastService that doesn't use timers or rendering.
class FakeScreencastService extends ScreencastService {
  FakeScreencastService()
      : super(
            frameCapturer: (_, {int? targetWidth, int? targetHeight}) async =>
                null);

  Future<void> Function(ScreencastFrame frame)? onFrameCallback;

  @override
  void start({
    required Future<void> Function(ScreencastFrame frame) onFrame,
    Duration interval = const Duration(milliseconds: 40),
  }) {
    onFrameCallback = onFrame;
  }

  @override
  bool get isActive => onFrameCallback != null;

  @override
  Future<void> stop() async {
    onFrameCallback = null;
  }

  /// Simulate delivering a frame from the capture loop.
  Future<void> deliverFrame(ScreencastFrame frame) async {
    await onFrameCallback?.call(frame);
  }
}

/// Creates a fake [ScreencastFrame] with synthetic RGBA data.
ScreencastFrame fakeFrame({
  int timestampMs = 1000,
  int width = 4,
  int height = 2,
}) {
  final bytes = Uint8List(width * height * 4);
  bytes.fillRange(0, bytes.length, 0xAB);
  return ScreencastFrame(
    rgbaBytes: bytes,
    timestampMs: timestampMs,
    width: width,
    height: height,
  );
}

/// A fake WebSocket server that records received binary messages.
///
/// Simulates the MCP-side WebSocketFrameServer for testing.
class FakeWsServer {
  FakeWsServer._(this._httpServer, this.port, this.receivedMessages);

  final HttpServer _httpServer;

  /// The port this server is listening on.
  final int port;

  /// All binary messages received from the client.
  final List<Uint8List> receivedMessages;

  /// Binds an HTTP server on localhost with an OS-assigned port.
  static Future<FakeWsServer> bind() async {
    final received = <Uint8List>[];
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = FakeWsServer._(httpServer, httpServer.port, received);
    server._startListening();
    return server;
  }

  void _startListening() {
    _httpServer.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen((message) {
          if (message is List<int>) {
            receivedMessages.add(
              message is Uint8List ? message : Uint8List.fromList(message),
            );
          }
        });
      } else {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
      }
    });
  }

  /// Closes the server.
  Future<void> close() async {
    await _httpServer.close(force: true);
  }
}
