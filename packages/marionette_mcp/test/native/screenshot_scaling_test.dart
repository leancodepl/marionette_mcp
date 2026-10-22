import 'dart:convert';

import 'package:image/image.dart' as img;
import 'package:marionette_mcp/src/native_service/screenshot_scaling.dart';
import 'package:test/test.dart';

String _png(int width, int height) =>
    base64Encode(img.encodePng(img.Image(width: width, height: height)));

img.Image _decode(String pngBase64) => img.decodePng(base64Decode(pngBase64))!;

void main() {
  group('scaleScreenshot', () {
    test('returns a screenshot that fits as is, without a note', () {
      final png = _png(1080, 1920);

      final scaled = scaleScreenshot(png)!;

      expect(scaled.pngBase64, png);
      expect((scaled.width, scaled.height), (1080, 1920));
      expect(scaled.isDownscaled, isFalse);
      expect(scaled.note, isNull);
    });

    test('fits a larger screenshot in 2000x2000 like Flutter, with a note', () {
      final scaled = scaleScreenshot(_png(1320, 2868))!;

      final image = _decode(scaled.pngBase64);
      expect((image.width, image.height), (920, 2000));
      expect((scaled.screenWidth, scaled.screenHeight), (1320, 2868));
      expect(scaled.factor, closeTo(1.435, 0.001));
      expect(
        scaled.note,
        'Screenshot 920x2000, downscaled from the 1320x2868 screen; multiply '
        'image coordinates by 1.435 for native x/y.',
      );
    });

    test('scales a landscape screenshot by its width', () {
      final scaled = scaleScreenshot(_png(2868, 1320))!;

      expect((scaled.width, scaled.height), (2000, 920));
    });

    test('returns null for data that is not a PNG', () {
      expect(scaleScreenshot(base64Encode(utf8.encode('png'))), isNull);
      expect(scaleScreenshot('not base64!'), isNull);
    });
  });
}
