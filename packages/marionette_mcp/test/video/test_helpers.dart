import 'dart:typed_data';

import 'package:marionette_mcp/src/video/frame_protocol.dart';
import 'package:marionette_mcp/src/video/video_recorder.dart';

/// Creates a raw RGBA frame (all white) for testing.
Uint8List createTestRgba(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  bytes.fillRange(0, bytes.length, 255);
  return bytes;
}

/// A simple mock sink that records all written frames.
class MockFfmpegSink implements FfmpegSink {
  final List<Uint8List> writtenFrames = [];

  @override
  void writeFrame(Uint8List data) {
    writtenFrames.add(data);
  }
}

/// Encodes a complete MRNT frame message (header + RGBA payload).
///
/// Used by transport tests (TCP, WebSocket) and protocol tests.
Uint8List encodeTestFrame({
  int width = 2,
  int height = 2,
  int timestampMs = 0,
  int? fillByte,
}) {
  final payloadLength = width * height * 4;
  final header = FrameHeader(
    frameLength: payloadLength,
    width: width,
    height: height,
    timestampMs: timestampMs,
  );
  final headerBytes = header.encode();
  final payload = Uint8List(payloadLength);
  if (fillByte != null) {
    payload.fillRange(0, payloadLength, fillByte);
  }
  return Uint8List.fromList([...headerBytes, ...payload]);
}

/// A sink that throws StateError after [failAfter] successful writes.
class FailingFfmpegSink implements FfmpegSink {
  FailingFfmpegSink({required this.failAfter});

  final int failAfter;
  int _writeCount = 0;
  final List<Uint8List> writtenFrames = [];

  @override
  void writeFrame(Uint8List data) {
    _writeCount++;
    if (_writeCount > failAfter) {
      throw StateError('Cannot write frame: ffmpeg has exited');
    }
    writtenFrames.add(data);
  }
}
