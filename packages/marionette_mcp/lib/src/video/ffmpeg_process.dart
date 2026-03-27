import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart' as logging;

import 'package:marionette_mcp/src/video/video_options.dart';
import 'package:marionette_mcp/src/video/video_recorder.dart';

final _logger = logging.Logger('FfmpegProcess');

/// Exception thrown when ffmpeg exits with a non-zero exit code.
class FfmpegException implements Exception {
  FfmpegException(this.message);

  final String message;

  @override
  String toString() => 'FfmpegException: $message';
}

/// Manages an ffmpeg child process for video encoding.
///
/// Accepts raw RGBA frames via stdin and produces a VP8/WebM video file.
class FfmpegProcess implements FfmpegSink, FfmpegCloseable {
  FfmpegProcess._(this._process, this._stderrBuffer) {
    unawaited(
      _process.exitCode.then((code) {
        _hasExited = true;
        _exitCode = code;
      }),
    );
  }

  final Process _process;
  final StringBuffer _stderrBuffer;
  bool _hasExited = false;
  int? _exitCode;

  /// Checks if ffmpeg is available on the system PATH.
  static Future<bool> isAvailable({String ffmpegPath = 'ffmpeg'}) async {
    try {
      final result = await Process.run(ffmpegPath, ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Creates and immediately spawns the ffmpeg process.
  static Future<FfmpegProcess> start({
    required VideoOptions options,
    String ffmpegPath = 'ffmpeg',
  }) async {
    final args = buildArgs(options);

    final process = await Process.start(
      ffmpegPath,
      args,
      mode: ProcessStartMode.normal,
    );

    final stderrBuffer = StringBuffer();
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrBuffer.writeln(line);
          _logger.fine('ffmpeg: $line');
        });

    return FfmpegProcess._(process, stderrBuffer);
  }

  /// Writes a single raw RGBA frame to ffmpeg's stdin.
  ///
  /// Does not flush after each frame — relies on Dart's IOSink buffering
  /// and OS pipe buffering to batch writes. Flushing happens in [close].
  @override
  void writeFrame(Uint8List frameData) {
    if (_hasExited) {
      throw StateError('Cannot write frame: ffmpeg has exited');
    }
    _process.stdin.add(frameData);
  }

  /// Gracefully closes ffmpeg by closing stdin and waiting for exit.
  ///
  /// Returns the exit code. 0 = success.
  @override
  Future<int> close() async {
    if (_hasExited) return _exitCode!;

    try {
      await _process.stdin.flush();
      await _process.stdin.close();
    } catch (_) {
      // stdin may already be broken if ffmpeg crashed. Ignore and
      // fall through to wait for the exit code.
    }

    final code = await _process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _process.kill();
        return -1;
      },
    );

    _hasExited = true;
    _exitCode = code;

    if (code != 0) {
      throw FfmpegException(
        'ffmpeg exited with code $code: ${_stderrBuffer.toString()}',
      );
    }

    return code;
  }

  /// Forcefully kills the ffmpeg process.
  void kill() {
    _process.kill();
  }

  /// Whether the process has exited.
  bool get hasExited => _hasExited;

  /// A future that completes when the process exits.
  Future<int> get exitCode => _process.exitCode;

  /// Builds the ffmpeg command-line arguments for the given options.
  static List<String> buildArgs(VideoOptions options) {
    return [
      // Input configuration: raw RGBA frames via stdin
      '-loglevel', 'error',
      '-f', 'rawvideo',
      '-pix_fmt', 'rgba',
      '-s', '${options.width}x${options.height}',
      '-r', '${options.fps}',
      '-i', 'pipe:0',

      // Output configuration
      '-y',
      '-an',

      // Convert RGBA input to YUV420P for VP8 encoding
      '-pix_fmt', 'yuv420p',

      // VP8 codec settings
      '-c:v', 'vp8',
      '-qmin', '0',
      '-qmax', '50',
      '-crf', '8',
      '-deadline', 'realtime',
      '-speed', '8',
      '-b:v', '1M',
      '-threads', '1',

      // Output file
      options.outputFile,
    ];
  }
}
