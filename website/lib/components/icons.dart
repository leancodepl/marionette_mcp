import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'icons.scopes.dart';

/// Inline SVG icons, drawn with Jaspr's typed SVG components so they hydrate
/// cleanly inside client components too.
enum Icon {
  copy(['M9 9h10v10H9z', 'M5 15V5h10']),
  check(['m5 12 5 5L20 7']),
  github([
    'M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.15-1.11-1.46-1.11-1.46-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2z',
  ]),
  arrow(['M5 12h14', 'm13 6 6 6-6 6']),
  external(['M14 4h6v6', 'M20 4 10 14', 'M18 13v7H4V6h7']),
  terminal(['m4 17 6-6-6-6', 'M12 19h8']),
  eye([
    'M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z',
    'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
  ]),
  pointer([
    'M9 12V5a1.5 1.5 0 0 1 3 0v6',
    'M12 11V9.5a1.5 1.5 0 0 1 3 0V11',
    'M15 11a1.5 1.5 0 0 1 3 0v4a6 6 0 0 1-6 6h-.6a6 6 0 0 1-4.8-2.4L4.3 15a1.6 1.6 0 0 1 2.5-2l2.2 2',
  ]),
  verify(['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'm8.5 12 2.5 2.5 5-5']),
  refresh([
    'M20 11a8 8 0 0 0-14.6-4.5L4 8',
    'M4 3v5h5',
    'M4 13a8 8 0 0 0 14.6 4.5L20 16',
    'M20 21v-5h-5',
  ]),
  phone([
    'M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z',
    'M11 18h2',
  ]),
  plug(['M9 2v5', 'M15 2v5', 'M6 7h12v4a6 6 0 0 1-12 0z', 'M12 17v5']),
  textSize([
    'M3 7V5h11v2',
    'M8.5 5v14',
    'M6.5 19h4',
    'M14 12v-1.5h7V12',
    'M17.5 10.5V19',
    'M16 19h3',
  ]),
  sparkle([
    'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z',
    'M19 17l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z',
  ]),
  bug([
    'M8.5 9a3.5 3.5 0 0 1 7 0v5a3.5 3.5 0 0 1-7 0z',
    'M12 10v8',
    'M4 13h4.5',
    'M15.5 13H20',
    'M5 7.5l3.5 1.5',
    'M19 7.5 15.5 9',
    'M5 19l3.5-2',
    'M19 19l-3.5-2',
  ]),
  play(['M7 4.5v15l12.5-7.5z']),
  step(['M5 4.5v15', 'M9 4.5v15l10.5-7.5z']),
  bolt(['M13 2 4 14h7l-1 8 9-12h-7z']),
  shield(['M12 3 4 6v6c0 5 3.4 8.4 8 9 4.6-.6 8-4 8-9V6z', 'm9 12 2 2 4-4']),
  git([
    'M6 3v12',
    'M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M18 9a9 9 0 0 1-9 9',
  ]),
  file(['M14 3H6v18h12V7z', 'M14 3v4h4', 'M9 13h6', 'M9 17h6']),
  layers(['m12 3 9 5-9 5-9-5z', 'm3 13 9 5 9-5', 'm3 17 9 5 9-5']),
  gauge(['M5 19a9 9 0 1 1 14 0', 'M12 13l4-5']),
  cog([
    'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.5-2.4 1a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.5 2 1.5A7 7 0 0 0 5 12a7 7 0 0 0 .1 1.2l-2 1.5 2 3.5 2.4-1a7 7 0 0 0 2 1.2L10 21h4l.5-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.5-2-1.5A7 7 0 0 0 19 12z',
  ]),
  braces([
    'M8 3H7a2 2 0 0 0-2 2v4a2 2 0 0 1-2 2 2 2 0 0 1 2 2v4a2 2 0 0 0 2 2h1',
    'M16 3h1a2 2 0 0 1 2 2v4a2 2 0 0 0 2 2 2 2 0 0 0-2 2v4a2 2 0 0 1-2 2h-1',
  ]),
  book(['M4 4h7v16H4z', 'M13 4h7v16h-7z', 'M11 4a2 2 0 0 1 2 0']),
  search(['M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z', 'm20 20-4-4']);

  Icon(this.paths);

  final List<String> paths;

  Component build({int size = 20, String? classes}) => svg(
    classes: classes,
    attributes: {
      'viewBox': '0 0 24 24',
      'width': '$size',
      'height': '$size',
      'fill': 'none',
      'stroke': 'currentColor',
      'stroke-width': '1.75',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
      'aria-hidden': 'true',
      'focusable': 'false',
    },
    [
      for (final d in paths) path(attributes: {'d': d}, const []),
    ],
  );
}

/// The Marionette word mark, the brand's own logo file: the bird on its
/// strings next to the name, drawn for dark backgrounds.
Component logo({bool large = false}) => img(
  src: 'images/brand/logo.svg',
  alt: 'Marionette',
  classes: (large ? Logo.root + Logo.large : Logo.root).name,
  width: large ? 228 : 152,
  height: large ? 48 : 32,
);

/// The classes of [logo]. The social card resizes it.
@scopedCss
abstract final class Logo {
  static const _class = _$LogoScope;

  static final root = _class.root;
  static final large = _class('large');

  @css
  static List<StyleRule> get styles => [
    css(root.selector).styles(display: .block, width: .auto, height: 32.px),
    css(large.selector).styles(height: 48.px),
  ];
}
