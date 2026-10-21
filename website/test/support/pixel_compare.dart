/// Pixel comparison for golden images, after pixelmatch: colors are compared
/// in the YIQ space so antialiasing passes and a new color does not.
library;

import 'package:image/image.dart' as img;

/// Per-pixel color distance (in the YIQ space, on a 0–1 scale) below which
/// two pixels count as the same. 0.1 forgives antialiasing, not a new color.
const colorThreshold = 0.1;

/// Counts the pixels of [actual] that differ from [expected] beyond
/// [colorThreshold], and draws them in red on a faded copy of [expected].
({int differing, img.Image diff}) compare(
  img.Image expected,
  img.Image actual,
) {
  final diff = img.Image(width: expected.width, height: expected.height);
  const maxDelta = 35215 * colorThreshold * colorThreshold;
  var differing = 0;
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      final a = _rgba(expected, x, y);
      final b = _rgba(actual, x, y);
      if (_colorDelta(a, b) > maxDelta) {
        differing++;
        diff.setPixelRgb(x, y, 255, 0, 0);
      } else {
        final gray = 255 - ((255 - _luma(a)) * 0.1).round();
        diff.setPixelRgb(x, y, gray, gray, gray);
      }
    }
  }
  return (differing: differing, diff: diff);
}

typedef _Rgba = (double, double, double, double);

_Rgba _rgba(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  final alpha = image.numChannels == 4 ? pixel.a.toDouble() : 255.0;
  return (pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble(), alpha);
}

// Both pixels are blended onto white and compared in the YIQ space, weighting
// luma over chroma.
double _colorDelta(_Rgba a, _Rgba b) {
  final (r1, g1, b1) = _blend(a);
  final (r2, g2, b2) = _blend(b);
  final y = _y(r1, g1, b1) - _y(r2, g2, b2);
  final i = _i(r1, g1, b1) - _i(r2, g2, b2);
  final q = _q(r1, g1, b1) - _q(r2, g2, b2);
  return 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q;
}

(double, double, double) _blend(_Rgba c) {
  final (r, g, b, a) = c;
  final alpha = a / 255;
  return (
    255 + (r - 255) * alpha,
    255 + (g - 255) * alpha,
    255 + (b - 255) * alpha,
  );
}

int _luma(_Rgba c) {
  final (r, g, b) = _blend(c);
  return _y(r, g, b).round();
}

double _y(double r, double g, double b) =>
    r * 0.29889531 + g * 0.58662247 + b * 0.11448223;
double _i(double r, double g, double b) =>
    r * 0.59597799 - g * 0.27417610 - b * 0.32180189;
double _q(double r, double g, double b) =>
    r * 0.21147017 - g * 0.52261711 + b * 0.31114694;
