import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A single captured frame with metadata.
class ScreencastFrame {
  ScreencastFrame({
    required this.rgbaBytes,
    required this.timestampMs,
    required this.width,
    required this.height,
  });

  /// Raw RGBA pixel data.
  final Uint8List rgbaBytes;

  /// Monotonic elapsed timestamp in milliseconds since screencast started.
  final int timestampMs;

  /// Viewport width in physical pixels.
  final int width;

  /// Viewport height in physical pixels.
  final int height;
}

/// Result of capturing a single frame from a RenderView.
class CapturedFrame {
  CapturedFrame({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// Raw RGBA pixel data.
  final Uint8List bytes;

  /// Image width in physical pixels.
  final int width;

  /// Image height in physical pixels.
  final int height;
}

/// Function that captures image bytes from a RenderView.
///
/// If [targetWidth] and [targetHeight] are provided, the capture should
/// scale to those dimensions. Otherwise captures at the view's native size.
typedef FrameCapturer = Future<CapturedFrame?> Function(
  RenderView renderView, {
  int? targetWidth,
  int? targetHeight,
});

/// Default frame capturer that uses the real rendering pipeline.
///
/// If [targetWidth] and [targetHeight] are provided, the GPU scales the
/// scene to those dimensions. Otherwise captures at the view's physical size.
/// Returns raw RGBA bytes via [ImageByteFormat.rawRgba] — essentially free
/// compared to PNG encoding.
Future<CapturedFrame?> defaultFrameCapturer(
  RenderView renderView, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final flutterView = renderView.flutterView;
  final size = flutterView.physicalSize;

  if (size.isEmpty) return null;

  // ignore: invalid_use_of_protected_member
  final layer = renderView.layer;
  if (layer == null) return null;

  final width = targetWidth ?? size.width.round();
  final height = targetHeight ?? size.height.round();
  if (width <= 0 || height <= 0) return null;

  final builder = ui.SceneBuilder();
  ui.Scene? scene;
  ui.Image? image;

  try {
    layer.addToScene(builder);
    scene = builder.build();
    image = await scene.toImage(width, height);

    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      debugPrint(
        'defaultFrameCapturer: toByteData returned null — '
        'requested=${width}x$height',
      );
      return null;
    }

    return CapturedFrame(
      bytes: byteData.buffer.asUint8List(),
      width: width,
      height: height,
    );
  } finally {
    image?.dispose();
    scene?.dispose();
  }
}

/// Captures frames from the Flutter render tree at regular intervals.
class ScreencastService {
  ScreencastService({FrameCapturer? frameCapturer, this.maxSize})
      : _frameCapturer = frameCapturer ?? defaultFrameCapturer;

  /// Optional max size constraint. Frames are downscaled to fit if set.
  final Size? maxSize;

  final FrameCapturer _frameCapturer;
  bool _isActive = false;
  Timer? _timer;
  Future<void> Function(ScreencastFrame frame)? _onFrame;
  bool _awaitingAck = false;
  Future<void>? _inFlightCallback;
  Stopwatch? _stopwatch;
  int _captureAttempts = 0;
  int _captureFailures = 0;

  /// Whether the screencast is currently active.
  bool get isActive => _isActive;

  /// Starts capturing frames. Calls [onFrame] for each captured frame.
  /// The [onFrame] callback returns a Future — the next frame is not
  /// captured until the previous callback completes (back-pressure).
  void start({
    required Future<void> Function(ScreencastFrame frame) onFrame,
    Duration interval = const Duration(milliseconds: 40),
  }) {
    if (_isActive) {
      throw StateError('ScreencastService is already active');
    }
    _isActive = true;
    _onFrame = onFrame;
    _awaitingAck = false;
    _captureAttempts = 0;
    _captureFailures = 0;
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(interval, (_) => _onTick());
  }

  /// Stops capturing frames. Returns after the last in-flight frame completes.
  Future<void> stop() async {
    _isActive = false;
    _timer?.cancel();
    _timer = null;
    await _inFlightCallback;
    _stopwatch?.stop();
    _stopwatch = null;
    _onFrame = null;
  }

  void _onTick() {
    if (!_isActive || _awaitingAck) return;

    final renderViews = WidgetsBinding.instance.renderViews;
    if (renderViews.isEmpty) return;

    _awaitingAck = true;

    _inFlightCallback = _captureAndDeliver().whenComplete(() {
      _awaitingAck = false;
    });
  }

  Future<void> _captureAndDeliver() async {
    // Capture stopwatch reference early so a concurrent stop() cannot null it
    // between the check and the read.
    final stopwatch = _stopwatch;
    if (stopwatch == null) return;

    final renderView = WidgetsBinding.instance.renderViews.first;
    final physicalSize = renderView.flutterView.physicalSize;
    final nativeWidth = physicalSize.width.round();
    final nativeHeight = physicalSize.height.round();

    // Compute target dimensions, applying maxSize constraint if set.
    final (targetWidth, targetHeight) =
        computeFrameSize(nativeWidth, nativeHeight, maxSize);

    _captureAttempts++;

    // Log first capture attempt to help diagnose dimension issues.
    if (_captureAttempts == 1) {
      debugPrint(
        'Screencast: first capture attempt — '
        'viewport=${nativeWidth}x$nativeHeight, '
        'target=${targetWidth}x$targetHeight, '
        'maxSize=$maxSize',
      );
    }

    // Capture at target dimensions — GPU does the scaling, and rawRgba
    // avoids any encoding overhead.
    CapturedFrame? captured;
    try {
      captured = await _frameCapturer(
        renderView,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
    } catch (e) {
      _captureFailures++;
      if (_captureFailures == 1 || _captureFailures % 50 == 0) {
        debugPrint(
          'Screencast: frame capture threw '
          '($_captureFailures/$_captureAttempts failures) — '
          'target=${targetWidth}x$targetHeight, '
          'viewport=${nativeWidth}x$nativeHeight: $e',
        );
      }
      return;
    }
    if (captured == null) {
      _captureFailures++;
      // Log first failure and then periodically to avoid flooding.
      if (_captureFailures == 1 || _captureFailures % 50 == 0) {
        debugPrint(
          'Screencast: frame capture returned null '
          '($_captureFailures/$_captureAttempts failures) — '
          'target=${targetWidth}x$targetHeight, '
          'viewport=${nativeWidth}x$nativeHeight',
        );
      }
      return;
    }

    final frame = ScreencastFrame(
      rgbaBytes: captured.bytes,
      timestampMs: stopwatch.elapsedMilliseconds,
      width: captured.width,
      height: captured.height,
    );

    await _onFrame?.call(frame);
  }

  /// Computes the even-aligned frame dimensions for a given viewport and
  /// optional bounding-box constraint.
  ///
  /// This is the single source of truth for frame dimensions. Both the Flutter
  /// screencast servers (to report `frameWidth`/`frameHeight`) and the internal
  /// capture loop use this method so that the reported dimensions always match
  /// what frames are actually captured at.
  static (int, int) computeFrameSize(int width, int height, Size? maxSize) {
    if (maxSize != null && (width > maxSize.width || height > maxSize.height)) {
      final scale = math.min(
        maxSize.width / width,
        maxSize.height / height,
      );
      width = (width * scale).floor();
      height = (height * scale).floor();
    }

    return (math.max(2, width & ~1), math.max(2, height & ~1));
  }
}
