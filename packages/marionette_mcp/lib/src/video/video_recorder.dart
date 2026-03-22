import 'dart:typed_data';

/// Interface for writing frames to an ffmpeg process.
abstract class FfmpegSink {
  void writeFrame(Uint8List data);
}

/// Interface for closing an ffmpeg process.
abstract class FfmpegCloseable {
  Future<int> close();
}

/// Options for the [VideoRecorder].
class VideoRecorderOptions {
  VideoRecorderOptions({this.fps = 25, this.width = 800, this.height = 600});

  /// Output frame rate in frames per second.
  final int fps;

  /// Video width in pixels.
  final int width;

  /// Video height in pixels.
  final int height;
}

/// Converts variable-rate frame input to constant-rate output for ffmpeg.
///
/// Port of Playwright's VideoRecorder class.
class VideoRecorder {
  VideoRecorder(this._options, this._ffmpegSink);

  final VideoRecorderOptions _options;
  final FfmpegSink _ffmpegSink;

  double? _firstTimestamp;
  int _lastFrameNumber = 0;
  Uint8List? _lastFrameData;
  bool _isStopped = false;
  bool _hasFailed = false;
  final Stopwatch _lastWriteStopwatch = Stopwatch();

  int _timestampToFrameNumber(double timestamp) {
    _firstTimestamp ??= timestamp;
    return ((timestamp - _firstTimestamp!) * _options.fps).floor();
  }

  /// Write a new frame with its wall-clock timestamp.
  ///
  /// [frameData] is the raw RGBA bytes.
  /// [timestamp] is the wall-clock time in seconds.
  void writeFrame(Uint8List frameData, double timestamp) {
    if (_isStopped || _hasFailed) return;
    _lastWriteStopwatch.reset();
    _lastWriteStopwatch.start();
    try {
      _writeFrameInternal(frameData, timestamp);
    } catch (_) {
      _hasFailed = true;
      rethrow;
    }
  }

  void _writeFrameInternal(Uint8List frameData, double timestamp) {
    final frameNumber = _timestampToFrameNumber(timestamp);

    if (_lastFrameData != null) {
      final repeatCount = frameNumber - _lastFrameNumber;
      for (var i = 0; i < repeatCount; i++) {
        _ffmpegSink.writeFrame(_lastFrameData!);
      }
    }

    _lastFrameNumber = frameNumber;
    _lastFrameData = frameData;
  }

  /// Stop the recorder. Pads the final frame and flushes all pending writes.
  ///
  /// Does NOT close the ffmpeg process — caller is responsible for that.
  void stop() {
    if (_isStopped) return;
    _isStopped = true;

    // If the sink has already failed (e.g., ffmpeg crashed), skip padding
    // writes — they would just hit the same error.
    if (_hasFailed) return;

    if (_lastFrameData == null) {
      // No frames ever received — create a synthetic white frame so ffmpeg
      // produces a valid (if boring) output file.
      final whiteFrame = createWhiteRgba(_options.width, _options.height);
      _writeFrameInternal(whiteFrame, 0.0);
    }

    // Pad with the monotonic time since the last write, minimum 1 second.
    final elapsed = _lastWriteStopwatch.isRunning
        ? _lastWriteStopwatch.elapsedMilliseconds / 1000.0
        : 1.0;
    final addTime = elapsed < 1.0 ? 1.0 : elapsed;
    final lastTimestamp = _firstTimestamp! + _lastFrameNumber / _options.fps;
    _writeFrameInternal(_lastFrameData!, lastTimestamp + addTime);
  }

  /// Whether [stop] has been called.
  bool get isStopped => _isStopped;

  /// Whether the recorder has failed due to a sink error (e.g., ffmpeg crash).
  bool get hasFailed => _hasFailed;

  /// Creates a white RGBA image of the given dimensions.
  static Uint8List createWhiteRgba(int width, int height) {
    final bytes = Uint8List(width * height * 4);
    bytes.fillRange(0, bytes.length, 255);
    return bytes;
  }
}
