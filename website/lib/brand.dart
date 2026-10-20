/// The favicon, built from the brand's own sygnet. Reads files, so only the
/// asset test imports it, never a component.
library;

import 'dart:io';

import 'package:marionette_website/palette.dart';

/// The sygnet (the bird on its strings, 377×500) centered in a black square,
/// [size] pixels on a side with corners of [radius] in the 64-unit viewBox.
/// The bird fills the inner 80% of the height, so the manifest icons pass as
/// maskable. Written to `web/favicon.svg` and rasterized into the other icons
/// by `test/assets_test.dart`.
String faviconSvg({int size = 64, int radius = 14}) {
  final sygnet = File('web/images/brand/sygnet.svg').readAsStringSync();
  final inner = sygnet.substring(
    sygnet.indexOf('>') + 1,
    sygnet.lastIndexOf('</svg>'),
  );
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" '
      'width="$size" height="$size">'
      '<rect width="64" height="64" rx="$radius" fill="${Palette.black.hex}"/>'
      '<svg x="12.7" y="6.4" width="38.6" height="51.2" viewBox="0 0 377 500" '
      'fill="none">$inner</svg></svg>';
}
