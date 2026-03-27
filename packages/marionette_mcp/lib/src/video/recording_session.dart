import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart' as logging;

import 'package:marionette_mcp/src/video/video_recorder.dart';

final _logger = logging.Logger('RecordingSession');

/// A single frame from a frame source.
class SourceFrame {
  const SourceFrame({required this.rgbaBytes, required this.timestampMs});

  /// Raw RGBA pixel data.
  final Uint8List rgbaBytes;

  /// Elapsed timestamp in milliseconds since the screencast started.
  final int timestampMs;
}

/// Abstraction over how frames are delivered to the recording session.
///
/// Implementations include [TcpFrameReader] (production) and test fakes.
abstract class FrameSource {
  Stream<SourceFrame> get frames;
  Future<void> close();
}

/// Result of a completed recording session.
class RecordingResult {
  const RecordingResult({
    required this.outputFile,
    required this.duration,
    required this.frameCount,
  });

  /// Path to the output video file.
  final String outputFile;

  /// Wall-clock duration of the recording.
  final Duration duration;

  /// Number of source frames received from the app.
  final int frameCount;
}

/// Manages an active recording session.
///
/// Consumes frames from a [FrameSource] stream, writes them to
/// [VideoRecorder] for timing normalization, and pipes to ffmpeg.
class RecordingSession {
  RecordingSession({
    required FrameSource frameSource,
    required VideoRecorder videoRecorder,
    required FfmpegCloseable ffmpegCloseable,
    required this.outputFile,
  }) : _frameSource = frameSource,
       _videoRecorder = videoRecorder,
       _ffmpegCloseable = ffmpegCloseable;

  final FrameSource _frameSource;
  final VideoRecorder _videoRecorder;
  final FfmpegCloseable _ffmpegCloseable;
  final String outputFile;

  int _frameCount = 0;
  bool _wasDisconnected = false;
  final Stopwatch _durationStopwatch = Stopwatch();
  RecordingResult? _result;
  Completer<RecordingResult>? _stopCompleter;
  Completer<void>? _consumeCompleter;
  StreamSubscription<SourceFrame>? _subscription;

  /// Whether the stream exited due to errors (app disconnect).
  bool get wasDisconnected => _wasDisconnected;

  /// Starts consuming frames from the source.
  ///
  /// Throws [StateError] if already started.
  void start() {
    if (_subscription != null) {
      throw StateError('RecordingSession is already started');
    }
    _durationStopwatch.start();
    _consumeCompleter = Completer<void>();
    var consecutiveErrors = 0;

    _subscription = _frameSource.frames.listen(
      (frame) {
        if (_videoRecorder.hasFailed) {
          _subscription?.cancel();
          if (!_consumeCompleter!.isCompleted) _consumeCompleter!.complete();
          return;
        }
        consecutiveErrors = 0;
        try {
          _videoRecorder.writeFrame(
            frame.rgbaBytes,
            frame.timestampMs / 1000.0,
          );
        } catch (e) {
          _logger.warning('Error writing frame to recorder: $e');
          _subscription?.cancel();
          if (!_consumeCompleter!.isCompleted) _consumeCompleter!.complete();
          return;
        }
        _frameCount++;
      },
      onError: (Object error) {
        consecutiveErrors++;
        _logger.warning('Error receiving frame: $error');
        if (consecutiveErrors >= _maxConsecutiveErrors) {
          _logger.severe(
            'App appears disconnected after $consecutiveErrors '
            'consecutive errors — stopping recording',
          );
          _wasDisconnected = true;
          _subscription?.cancel();
          if (!_consumeCompleter!.isCompleted) _consumeCompleter!.complete();
        }
      },
      onDone: () {
        if (!_consumeCompleter!.isCompleted) _consumeCompleter!.complete();
      },
    );
  }

  /// Stops the recording session. Returns recording metadata.
  ///
  /// Idempotent — calling stop() multiple times or concurrently returns
  /// the same result. Only the first call runs the actual stop logic.
  Future<RecordingResult> stop() async {
    if (_result != null) return _result!;
    if (_stopCompleter != null) return _stopCompleter!.future;

    _stopCompleter = Completer<RecordingResult>();

    try {
      // Cancel the stream subscription and wait for in-flight processing.
      await _subscription?.cancel();
      if (_consumeCompleter != null && !_consumeCompleter!.isCompleted) {
        _consumeCompleter!.complete();
      }

      // Close the frame source (TCP socket / WebSocket server) so it
      // doesn't leak connections after the session ends.
      await _frameSource.close();

      _videoRecorder.stop();
      await _ffmpegCloseable.close();

      _durationStopwatch.stop();
      _result = RecordingResult(
        outputFile: outputFile,
        duration: _durationStopwatch.elapsed,
        frameCount: _frameCount,
      );
      _stopCompleter!.complete(_result);
    } catch (e) {
      _stopCompleter!.completeError(e);
      rethrow;
    }

    return _result!;
  }

  /// At 25 fps (~40 ms/frame), 10 consecutive errors means ~400 ms of
  /// uninterrupted failures — enough to distinguish a disconnected app from
  /// transient hiccups without cutting recordings short.
  static const _maxConsecutiveErrors = 10;
}
