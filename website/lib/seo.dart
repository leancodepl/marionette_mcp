/// Everything a crawler or link unfurler reads: metadata, social cards and
/// JSON-LD structured data. Site-wide pieces live in [siteHead]; each page
/// adds its own title, description and canonical URL through [pageHead].
library;

import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/palette.dart';
import 'package:marionette_website/site.dart';
import 'package:marionette_website/tracking.dart';

/// Site-wide `<meta name>` tags rendered by the `Document`.
final siteMeta = {
  'author': 'LeanCode',
  'robots': 'index, follow, max-image-preview:large',
  'theme-color': Palette.black.hex,
  'color-scheme': 'dark',
  'application-name': siteName,
  'generator': 'Jaspr',
};

/// `web/site.webmanifest`, written by `test/assets_test.dart` so its colors
/// follow the palette.
final webManifest =
    '${const JsonEncoder.withIndent('  ').convert({
      'name': '$siteName — $tagline',
      'short_name': siteName,
      'description': 'Lets AI agents see, drive and verify a running Flutter app.',
      'start_url': './',
      'display': 'browser',
      'background_color': Palette.black.hex,
      'theme_color': Palette.black.hex,
      'icons': [
        {'src': 'favicon.svg', 'sizes': 'any', 'type': 'image/svg+xml'},
        {'src': 'icon-192.png', 'sizes': '192x192', 'type': 'image/png', 'purpose': 'any maskable'},
        {'src': 'icon-512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'any maskable'},
      ],
    })}\n';

String get _ogImage => '${canonicalUrl}images/og.png';

/// The two variable fonts the design uses, served from `web/fonts/` (SIL Open
/// Font License, texts alongside the files) so no third-party stylesheet
/// blocks the first paint. Latin and Latin Extended subsets cover the site's
/// text; `swap` shows the fallback stack until they arrive.
const fontFaces = '''
@font-face{font-family:'Space Grotesk';font-style:normal;font-weight:300 700;font-display:swap;src:url(fonts/space-grotesk-latin.woff2) format('woff2');unicode-range:U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD}
@font-face{font-family:'Space Grotesk';font-style:normal;font-weight:300 700;font-display:swap;src:url(fonts/space-grotesk-latin-ext.woff2) format('woff2');unicode-range:U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:100 800;font-display:swap;src:url(fonts/jetbrains-mono-latin.woff2) format('woff2');unicode-range:U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD}
@font-face{font-family:'JetBrains Mono';font-style:normal;font-weight:100 800;font-display:swap;src:url(fonts/jetbrains-mono-latin-ext.woff2) format('woff2');unicode-range:U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF}
''';

/// `<head>` children shared by every page: icons, fonts, the social
/// card image and the structured data describing the package itself.
List<Component> siteHead({required String version}) => [
  if (isProduction) ...trackingHead,
  const link(rel: 'icon', href: 'favicon.ico', attributes: {'sizes': '32x32'}),
  const link(rel: 'icon', href: 'favicon.svg', type: 'image/svg+xml'),
  const link(
    rel: 'icon',
    href: 'favicon.png',
    type: 'image/png',
    attributes: {'sizes': '96x96'},
  ),
  const link(rel: 'apple-touch-icon', href: 'apple-touch-icon.png'),
  const link(rel: 'manifest', href: 'site.webmanifest'),
  const link(rel: 'sitemap', href: 'sitemap.xml', type: 'application/xml'),
  // The Latin subsets carry every glyph above the fold, so they are fetched
  // before the parser reaches the text that needs them.
  for (final font in ['space-grotesk-latin', 'jetbrains-mono-latin'])
    link(
      rel: 'preload',
      href: 'fonts/$font.woff2',
      as: 'font',
      type: 'font/woff2',
      attributes: const {'crossorigin': ''},
    ),
  const RawText('<style>$fontFaces</style>'),
  ..._properties({
    'og:type': 'website',
    'og:site_name': siteName,
    'og:locale': 'en_US',
    'og:image': _ogImage,
    'og:image:width': '1200',
    'og:image:height': '630',
    'og:image:alt':
        "Marionette — your agent's hands and eyes on a running Flutter app",
  }),
  const meta(name: 'twitter:card', content: 'summary_large_image'),
  meta(name: 'twitter:image', content: _ogImage),
  jsonLd(_softwareSourceCode(version)),
  jsonLd(_webSite()),
];

/// Per-page metadata: title, description, canonical URL and social card text,
/// plus any page-specific [structuredData].
Component pageHead({
  required String title,
  required String description,
  required String path,
  List<Map<String, Object?>> structuredData = const [],
}) {
  final url = '$canonicalUrl$path';
  return Document.head(
    title: title,
    meta: {
      'description': description,
      'twitter:title': title,
      'twitter:description': description,
    },
    children: [
      link(rel: 'canonical', href: url),
      ..._properties({
        'og:url': url,
        'og:title': title,
        'og:description': description,
      }),
      for (final data in structuredData) jsonLd(data),
    ],
  );
}

List<Component> _properties(Map<String, String> properties) => [
  for (final MapEntry(key: property, value: content) in properties.entries)
    meta(attributes: {'property': property, 'content': content}),
];

/// A `<script type="application/ld+json">` block.
Component jsonLd(Map<String, Object?> data) => script(
  attributes: const {'type': 'application/ld+json'},
  // Escape "</" so the JSON can never terminate the script element early.
  content: jsonEncode(data).replaceAll('</', r'<\/'),
);

Map<String, Object?> organization() => {
  '@type': 'Organization',
  'name': 'LeanCode',
  'url': 'https://leancode.co/',
  'logo': 'https://leancodepublic.blob.core.windows.net/public/wide.png',
  'sameAs': [
    'https://github.com/leancodepl',
    'https://pub.dev/publishers/leancode.co',
  ],
};

Map<String, Object?> _softwareSourceCode(String version) => {
  '@context': 'https://schema.org',
  '@type': ['SoftwareSourceCode', 'SoftwareApplication'],
  'name': siteName,
  'alternateName': 'Marionette MCP',
  'description': description,
  'url': canonicalUrl,
  'codeRepository': repoUrl,
  'programmingLanguage': 'Dart',
  'runtimePlatform': 'Flutter 3.27+',
  'applicationCategory': 'DeveloperApplication',
  'operatingSystem': 'Linux, macOS, Windows',
  'softwareVersion': version,
  'downloadUrl': pubMcpUrl,
  'installUrl': pubMcpUrl,
  'license': 'https://www.apache.org/licenses/LICENSE-2.0',
  'isAccessibleForFree': true,
  'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
  'keywords':
      'flutter, mcp, ai agent, claude code, cursor, testing, automation',
  'author': organization(),
  'maintainer': organization(),
  'image': _ogImage,
};

Map<String, Object?> _webSite() => {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  'name': siteName,
  'url': canonicalUrl,
  'description': description,
  'inLanguage': 'en',
  'publisher': organization(),
};
