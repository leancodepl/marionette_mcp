import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'package:marionette_flutter/src/services/screencast_service.dart';

/// Web-compatible frame capturer using [OffsetLayer.toImage].
///
/// The default capturer builds a raw [ui.Scene] and calls [scene.toImage],
/// which produces blank frames on Flutter web because the web renderer
/// doesn't support offline scene rasterization the same way native does.
///
/// This implementation uses [OffsetLayer.toImage] which goes through
/// Flutter's compositing pipeline and works correctly on web (CanvasKit/Skwasm).
/// Scaling is done via [pixelRatio] in a single rasterization pass to avoid
/// the overhead of a second toImage round-trip.
Future<CapturedFrame?> webFrameCapturer(
  RenderView renderView, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final flutterView = renderView.flutterView;
  final size = flutterView.physicalSize;

  if (size.isEmpty) return null;

  // ignore: invalid_use_of_protected_member
  final containerLayer = renderView.layer;
  if (containerLayer is! OffsetLayer) return null;

  final nativeWidth = size.width.round();
  final nativeHeight = size.height.round();
  final width = targetWidth ?? nativeWidth;
  final height = targetHeight ?? nativeHeight;
  if (width <= 0 || height <= 0) return null;

  // Use pixelRatio to scale in a single rasterization pass.
  // OffsetLayer.toImage multiplies the bounds by pixelRatio, so we compute
  // the ratio that produces the target dimensions directly.
  final double pixelRatio;
  if (width != nativeWidth || height != nativeHeight) {
    pixelRatio = math.min(width / nativeWidth, height / nativeHeight);
  } else {
    pixelRatio = 1.0;
  }

  final bounds =
      Offset.zero & Size(nativeWidth.toDouble(), nativeHeight.toDouble());

  ui.Image? image;
  try {
    image = await containerLayer.toImage(bounds, pixelRatio: pixelRatio);

    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      debugPrint(
        'webFrameCapturer: toByteData returned null — '
        'image=${image.width}x${image.height}, '
        'pixelRatio=$pixelRatio',
      );
      return null;
    }

    final imgW = image.width;
    final imgH = image.height;
    final rawBytes = byteData.buffer.asUint8List();

    // OffsetLayer.toImage with fractional pixelRatio may produce an image
    // whose dimensions differ from the requested target by a pixel or two
    // due to rounding. ffmpeg expects frames of exactly width×height, so we
    // crop/pad the raw RGBA buffer to match precisely. This is a cheap
    // row-copy — no second rasterization needed.
    if (imgW == width && imgH == height) {
      return CapturedFrame(bytes: rawBytes, width: width, height: height);
    }

    return CapturedFrame(
      bytes: _fitToSize(rawBytes, imgW, imgH, width, height),
      width: width,
      height: height,
    );
  } finally {
    image?.dispose();
  }
}

/// Crops or pads raw RGBA pixel data from [srcW]×[srcH] to [dstW]×[dstH].
///
/// Copies min(srcW, dstW) pixels per row for min(srcH, dstH) rows.
/// Any extra columns or rows in the destination are left as zeroes
/// (transparent black).
Uint8List _fitToSize(
  Uint8List src,
  int srcW,
  int srcH,
  int dstW,
  int dstH,
) {
  final dst = Uint8List(dstW * dstH * 4);
  final copyW = math.min(srcW, dstW);
  final copyH = math.min(srcH, dstH);
  final srcStride = srcW * 4;
  final dstStride = dstW * 4;
  final rowBytes = copyW * 4;

  for (var y = 0; y < copyH; y++) {
    final srcOffset = y * srcStride;
    final dstOffset = y * dstStride;
    dst.setRange(dstOffset, dstOffset + rowBytes, src, srcOffset);
  }

  return dst;
}
