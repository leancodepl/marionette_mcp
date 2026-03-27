import 'dart:async';
import 'dart:io';

import 'package:marionette_mcp/src/video/frame_protocol.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';

/// Connects to a TCP frame server and exposes received frames as a stream.
///
/// The server (running inside the Flutter app) pushes binary frames using the
/// MRNT frame protocol: a 20-byte header followed by raw RGBA pixel data.
class TcpFrameReader implements FrameSource {
  TcpFrameReader({required this.host, required this.port});

  final String host;
  final int port;

  Socket? _socket;
  final _assembler = FrameAssembler();
  final _controller = StreamController<SourceFrame>();

  /// Connects to the frame server.
  Future<void> connect() async {
    _socket = await Socket.connect(host, port);
    _socket!.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: true,
    );
  }

  @override
  Stream<SourceFrame> get frames => _controller.stream;

  /// Closes the connection and the frame stream.
  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } catch (_) {
        // Socket may already be closed.
      }
      socket.destroy();
    }
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _onData(List<int> data) {
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
}
