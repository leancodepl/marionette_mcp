import 'dart:math' as math;

/// Maximum bounding-box dimension for auto-sized video recordings.
///
/// When no explicit width/height is given, the viewport is scaled to fit
/// within this square bounding box while preserving aspect ratio.
const maxBoundingBox = 800;

/// Default bounding box for web recordings.
///
/// Flutter's CPU-only web renderer (headless Chrome, webGLVersion -1) hangs
/// when `toImage` is called on canvases above ~1.3M pixels. 1280x720 (0.92M)
/// provides a safe margin and is a standard video resolution.
const webDefaultMaxWidth = 1280;
const webDefaultMaxHeight = 720;
const _defaultViewport = (width: 800, height: 600);

/// Validates and normalizes video dimensions.
///
/// If [size] is provided, it is used directly (rounded down to even numbers).
/// Otherwise, [viewportSize] is scaled to fit within an 800x800 bounding box.
/// Falls back to 800x600 if no dimensions are given or viewport is invalid.
({int width, int height}) validateVideoSize({
  ({int width, int height})? size,
  ({int width, int height})? viewportSize,
}) {
  int width, height;

  if (size != null) {
    width = size.width;
    height = size.height;
  } else {
    final raw = viewportSize ?? _defaultViewport;
    final vp = (raw.width <= 0 || raw.height <= 0) ? _defaultViewport : raw;
    final scale = (maxBoundingBox / math.max(vp.width, vp.height)).clamp(
      0.0,
      1.0,
    );
    width = (vp.width * scale).floor();
    height = (vp.height * scale).floor();
  }

  return (width: math.max(2, width & ~1), height: math.max(2, height & ~1));
}

/// Configuration for a video recording session.
class VideoOptions {
  VideoOptions({
    required this.width,
    required this.height,
    required this.outputFile,
    this.fps = 25,
  }) {
    if (fps <= 0) {
      throw ArgumentError.value(fps, 'fps', 'Must be positive');
    }
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'Must be positive');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'Must be positive');
    }
    if (width.isOdd) {
      throw ArgumentError.value(width, 'width', 'Must be even');
    }
    if (height.isOdd) {
      throw ArgumentError.value(height, 'height', 'Must be even');
    }
    if (!outputFile.endsWith('.webm')) {
      throw ArgumentError.value(
        outputFile,
        'outputFile',
        'Output file must end with .webm',
      );
    }
  }

  /// Video width in pixels (always even).
  final int width;

  /// Video height in pixels (always even).
  final int height;

  /// Path to the output video file. Must end with .webm.
  final String outputFile;

  /// Output frame rate. Default 25 fps (matches Playwright).
  final int fps;
}
