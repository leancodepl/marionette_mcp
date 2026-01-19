import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Service for taking screenshots of the main app view using RenderView layers.
class ScreenshotService {
  ScreenshotService({this.maxScreenshotSize});

  final Size? maxScreenshotSize;

  /// Takes screenshots of all RenderViews in the app.
  ///
  /// This method attempts to capture the current state of all views
  /// by rendering their layer trees into images.
  ///
  /// Returns a list of base64 encoded PNG image strings.
  Future<List<String>> takeScreenshots() async {
    // Target all RenderViews and their corresponding FlutterViews
    final renderViews = WidgetsBinding.instance.renderViews;
    final imageFutures = <Future<String?>>[];

    // Prepare for async calls
    for (final renderView in renderViews) {
      final flutterView = renderView.flutterView;

      // Call takeImage asynchronously for each view
      final imageFuture = _takeImage(
        flutterView: flutterView,
        view: renderView,
      );
      imageFutures.add(imageFuture);
    }

    // Wait for all screenshots to complete and filter out failures (nulls)
    final images = (await Future.wait(
      imageFutures,
    ))
        .whereType<String>()
        .toList();

    return images;
  }

  @visibleForTesting
  static Size? calculateScaledSize(Size source, Size maxSize) {
    if (!_isValidSize(source) || !_isValidSize(maxSize)) {
      return null;
    }

    if (source.width <= maxSize.width && source.height <= maxSize.height) {
      return null;
    }

    final scale = math.min(
      maxSize.width / source.width,
      maxSize.height / source.height,
    );

    final targetWidth = (source.width * scale).floor();
    final targetHeight = (source.height * scale).floor();
    if (targetWidth < 1 || targetHeight < 1) {
      return null;
    }
    return Size(targetWidth.toDouble(), targetHeight.toDouble());
  }

  /// Takes a screenshot of a single RenderView.
  ///
  /// This method attempts to capture the current state of the view
  /// by rendering its layer tree into an image.
  ///
  /// Returns a base64 encoded PNG image string, or null if capture fails.
  Future<String?> _takeImage({
    required ui.FlutterView flutterView,
    required RenderView view,
  }) async {
    // ignore: invalid_use_of_protected_member
    if (view.debugNeedsPaint || view.layer == null) {
      debugPrint(
        'ScreenshotService: View needs paint or layer is null. Scheduling frame.',
      );
      // Schedule a frame to ensure the layer tree is built and painted.
      WidgetsBinding.instance.scheduleFrame();
      // Wait for the frame to likely complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // ignore: invalid_use_of_protected_member
    final layer = view.layer;
    if (layer == null) {
      debugPrint(
        'ScreenshotService: Skipping view: Layer is null after delay.',
      );
      return null;
    }

    // Get physical size for accurate rendering from the corresponding FlutterView.
    final size = flutterView.physicalSize;
    if (size.isEmpty) {
      debugPrint('ScreenshotService: Skipping view: Physical size is empty.');
      return null;
    }

    // Create a SceneBuilder and add the view's layer tree to it.
    final builder = ui.SceneBuilder();
    ui.Scene? scene;
    ui.Image? image;
    ui.Image? resizedImage;

    try {
      // The offset is zero because we want to capture the entire view from its origin.
      layer.addToScene(builder);

      // Build the scene.
      scene = builder.build();

      // Render the scene to an image.
      // Ensure width and height are integers and positive.
      final width = size.width.ceil();
      final height = size.height.ceil();

      if (width <= 0 || height <= 0) {
        debugPrint(
          'ScreenshotService: Skipping view: Invalid image dimensions ($width x $height).',
        );
        return null; // scene will be disposed in finally
      }

      image = await scene.toImage(width, height);

      final targetSize = maxScreenshotSize == null
          ? null
          : calculateScaledSize(
              Size(width.toDouble(), height.toDouble()),
              maxScreenshotSize!,
            );

      if (targetSize != null) {
        resizedImage = await _resizeImage(image, targetSize);
      }

      final imageToEncode = resizedImage ?? image;

      // Convert to PNG byte data.
      final byteData = await imageToEncode.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        debugPrint(
          'ScreenshotService: Successfully captured screenshot '
          '(${pngBytes.lengthInBytes} bytes).',
        );
        return base64Encode(pngBytes);
      } else {
        debugPrint(
          'ScreenshotService: Failed to get byte data for screenshot.',
        );
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('ScreenshotService: Error capturing screenshot: $e');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } finally {
      // Dispose image immediately after use.
      if (resizedImage != null && resizedImage != image) {
        resizedImage.dispose();
      }
      image?.dispose();
      // Ensure scene is always disposed.
      scene?.dispose();
    }
  }

  Future<ui.Image> _resizeImage(ui.Image image, Size targetSize) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    final srcRect = ui.Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dstRect = ui.Rect.fromLTWH(
      0,
      0,
      targetSize.width,
      targetSize.height,
    );

    canvas.drawImageRect(image, srcRect, dstRect, paint);

    final picture = recorder.endRecording();
    final resizedImage = await picture.toImage(
      targetSize.width.round(),
      targetSize.height.round(),
    );
    picture.dispose();
    return resizedImage;
  }

  static bool _isValidSize(Size size) {
    return size.width > 0 && size.height > 0;
  }
}
