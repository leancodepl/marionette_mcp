import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_mcp/src/video/frame_protocol.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';

/// Hosts a WebSocket server on localhost that accepts a single client
/// connection and parses incoming MRNT binary frames.
///
/// This is the MCP-side counterpart to [ScreencastWebServer] in the Flutter
/// web app. The Flutter app connects as a WebSocket client and pushes frames.
class WebSocketFrameServer implements FrameSource {
  WebSocketFrameServer({required this.port});

  /// The port this server listens on. Assigned at construction; call [start]
  /// to actually bind.
  final int port;

  HttpServer? _httpServer;
  StreamSubscription<HttpRequest>? _httpSubscription;
  WebSocket? _client;
  final _assembler = FrameAssembler();
  final _controller = StreamController<SourceFrame>();

  @override
  Stream<SourceFrame> get frames => _controller.stream;

  /// Binds the HTTP server and starts accepting WebSocket upgrades.
  ///
  /// Throws [StateError] if the server is already started (e.g. via [bind]).
  Future<void> start() async {
    if (_httpServer != null) {
      throw StateError('Server already started');
    }
    _httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _httpSubscription = _httpServer!.listen(_onRequest);
  }

  @override
  Future<void> close() async {
    await _httpSubscription?.cancel();
    _httpSubscription = null;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
    if (!_controller.isClosed) {
      // Don't await — a StreamController that was never subscribed to will
      // not complete its close() future (pending onCancel callback).
      unawaited(_controller.close());
    }
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        if (_client != null) {
          // Only one client is supported. Reject additional connections.
          request.response
            ..statusCode = HttpStatus.conflict
            ..close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(request);
        _client = ws;
        ws.listen(
          _onMessage,
          onDone: _onDone,
          onError: _onError,
          cancelOnError: true,
        );
      } else {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
      }
    } catch (e) {
      if (!_controller.isClosed) {
        _controller.addError(e);
      }
    }
  }

  void _onMessage(dynamic message) {
    final Uint8List data;
    if (message is List<int>) {
      data = message is Uint8List ? message : Uint8List.fromList(message);
    } else {
      return; // Ignore text messages.
    }

    _assembler.addData(data);
    for (final frame in _assembler.drain()) {
      _controller.add(
        SourceFrame(
          rgbaBytes: frame.rgbaBytes,
          timestampMs: frame.header.timestampMs,
        ),
      );
    }
  }

  void _onDone() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void _onError(Object error) {
    if (!_controller.isClosed) {
      _controller.addError(error);
      _controller.close();
    }
  }

  /// Binds a WebSocket server on an OS-assigned port and returns it.
  static Future<WebSocketFrameServer> bind() async {
    // Bind to port 0 to get an OS-assigned port, then read back the port.
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = WebSocketFrameServer(port: httpServer.port);
    server._httpServer = httpServer;
    server._httpSubscription = httpServer.listen(server._onRequest);
    return server;
  }
}
