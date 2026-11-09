import 'dart:convert';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Largest width and height of a native screenshot, in pixels — the same
/// default as `MarionetteConfiguration.maxScreenshotSize` for Flutter's
/// `take_screenshots`.
const maxNativeScreenshotSide = 2000;

/// A native screenshot ready to return, and how it relates to the screen.
class ScaledScreenshot {
  const ScaledScreenshot({
    required this.pngBase64,
    required this.width,
    required this.height,
    required this.screenWidth,
    required this.screenHeight,
  });

  final String pngBase64;

  /// Size of the returned image.
  final int width;
  final int height;

  /// Size of the screen it was captured from, in screen pixels — the units
  /// of `bounds` and of native `x`/`y`.
  final int screenWidth;
  final int screenHeight;

  bool get isDownscaled => width != screenWidth || height != screenHeight;

  /// Screen pixels per image pixel: multiply a point read off the image by
  /// this to get native `x`/`y`.
  double get factor => screenWidth / width;

  /// What the agent needs to map the image to native coordinates; null when
  /// the image is the screen 1:1.
  String? get note => isDownscaled
      ? 'Screenshot ${width}x$height, downscaled from the '
          '${screenWidth}x$screenHeight screen; multiply image coordinates '
          'by ${factor.toStringAsFixed(3)} for native x/y.'
      : null;
}

/// Downscales [pngBase64] to fit within [maxSide]×[maxSide], keeping the
/// aspect ratio, as Flutter's `take_screenshots` does. A screenshot that
/// already fits is returned as is, without re-encoding. Returns null when
/// [pngBase64] is not a PNG that can be decoded; the caller then returns it
/// unchanged.
ScaledScreenshot? scaleScreenshot(
  String pngBase64, {
  int maxSide = maxNativeScreenshotSide,
}) {
  final img.Image? image;
  try {
    image = img.decodePng(base64Decode(pngBase64));
  } on FormatException {
    return null;
  }
  if (image == null) return null;

  final width = image.width;
  final height = image.height;
  if (width <= maxSide && height <= maxSide) {
    return ScaledScreenshot(
      pngBase64: pngBase64,
      width: width,
      height: height,
      screenWidth: width,
      screenHeight: height,
    );
  }

  final scale = math.min(maxSide / width, maxSide / height);
  final targetWidth = math.max(1, (width * scale).floor());
  final targetHeight = math.max(1, (height * scale).floor());
  final resized = img.copyResize(
    image,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.average,
  );
  return ScaledScreenshot(
    pngBase64: base64Encode(img.encodePng(resized)),
    width: targetWidth,
    height: targetHeight,
    screenWidth: width,
    screenHeight: height,
  );
}
