/// The LeanCode palette, named as the design system names it. Every color on
/// the site derives from these swatches: the `:root` tokens in `styles.dart`,
/// the alpha variants for glows and borders, `favicon.svg` and the web
/// manifest. Change a value here and `UPDATE_GOLDENS=1 dart test` regenerates
/// the assets in `web/`.
library;

import 'package:jaspr/dom.dart';

/// A solid color as a packed `0xRRGGBB`, usable as a CSS [color], at an
/// [alpha], or written verbatim into SVG and JSON as [hex].
enum Palette {
  /// Primary surface. LeanCode is black-first; yellow is the exception.
  black(0x000000),

  /// Text and headings on black.
  white(0xffffff),

  /// Call to action and emphasis only. Text on it is always [black].
  ctaYellow(0xf0ff00),

  /// Body copy on dark surfaces.
  bodyGray(0xd8d8d4),

  /// Secondary text, captions, metadata.
  mutedGray(0xa3a3a0),

  /// Cards and panels on black, warm-tinted, edged with a [line] hairline.
  surface(0x151513),
  surface2(0x1d1d1a),

  /// Error and success signals, sparingly.
  error(0xe64239),
  success(0x80c340),

  // The site's own tints, derived from the palette rather than part of it.

  /// A section background a step above [black], for the footer.
  nearBlack(0x0a0a08),

  /// [ctaYellow] lifted for the primary button's hover.
  ctaYellowLight(0xf5ff4d);

  Palette(this.rgb);

  final int rgb;

  /// The 1px hairline between surfaces, and a stronger one for controls.
  static final line = white.alpha(0.12);
  static final lineStrong = white.alpha(0.2);

  Color get color => .value(rgb);

  /// `#rrggbb`.
  String get hex => color.value;

  Color alpha(double alpha) =>
      .rgba(rgb >> 16 & 0xff, rgb >> 8 & 0xff, rgb & 0xff, alpha);
}
