/// Rasterizes the site's assets: SVG marks and Jaspr components, drawn by a
/// pinned Chrome for Testing so every machine produces the same pixels.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:marionette_website/brand.dart';
import 'package:marionette_website/main.server.options.dart';
import 'package:marionette_website/palette.dart';
import 'package:marionette_website/seo.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

/// A headless browser that renders assets at exact pixel sizes.
///
/// Components are served over a loopback HTTP server rooted at `web/`, so
/// relative URLs such as the self-hosted fonts resolve as they do in
/// production; `file://` pages would refuse to load fonts from another
/// directory.
class AssetRenderer {
  AssetRenderer._(this._browser, this._server);

  /// The Chrome for Testing build every render uses. A different build can
  /// antialias differently, so bump it and regenerate the assets together.
  static const chromeVersion = '152.0.7977.42';

  final Browser _browser;
  final HttpServer _server;

  /// The HTML the server answers `/component.html` with.
  Uint8List? _page;

  /// Downloads [chromeVersion] into `.dart_tool/puppeteer` if needed and
  /// launches it. Also initializes Jaspr, so components render with the site's
  /// own styles.
  static Future<AssetRenderer> launch() async {
    Jaspr.initializeApp(options: defaultServerOptions);
    final chrome = await downloadChrome(version: chromeVersion);
    final browser = await puppeteer.launch(
      executablePath: chrome.executablePath,
      noSandboxFlag: true,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final renderer = AssetRenderer._(browser, server);
    server.listen(renderer._serve);
    return renderer;
  }

  Future<void> close() async {
    await _browser.close();
    await _server.close();
  }

  /// [faviconSvg] with corners of [radius], rendered at [size] pixels. With
  /// [transparent], the corners are see-through and the PNG keeps its alpha.
  Future<Uint8List> icon({
    required int size,
    required int radius,
    bool transparent = false,
  }) => _shoot(
    width: size,
    height: size,
    transparent: transparent,
    html: faviconSvg(size: size, radius: radius),
  );

  /// Renders [component] through Jaspr, with the site's styles and fonts, and
  /// screenshots the top-left [width]×[height] pixels. Every family
  /// in [fonts] must have loaded, or the render fails.
  Future<Uint8List> component(
    Component component, {
    required int width,
    required int height,
    List<String> fonts = const [],
  }) async {
    // Jaspr inlines the site's own rules into the head.
    final response = await renderComponent(
      Document(
        lang: 'en',
        head: const [RawText('<style>$fontFaces</style>')],
        body: component,
      ),
    );
    _page = response.body;

    final page = await _browser.newPage();
    try {
      await page.setViewport(.new(width: width, height: height));
      await page.goto(
        'http://${_server.address.host}:${_server.port}/component.html',
        wait: .load,
      );
      await page.evaluate<void>('() => document.fonts.ready');
      // document.fonts.check() is vacuously true when no face matches, so look
      // at the faces themselves: every family must be present and loaded.
      final loaded = await page.evaluate<List<Object?>>(
        '() => [...document.fonts]'
        '.filter((f) => f.status === "loaded")'
        '.map((f) => f.family.replace(/"/g, ""))',
      );
      for (final family in fonts) {
        if (!loaded.contains(family)) {
          throw StateError(
            'Web font not loaded: $family (loaded: ${loaded.join(', ')})',
          );
        }
      }
      return await page.screenshot(clip: .new(0, 0, width, height));
    } finally {
      await page.close();
    }
  }

  /// Answers `/component.html` with the last rendered page and everything
  /// else from `web/`, like the deployed site does.
  void _serve(HttpRequest request) {
    final response = request.response;
    final path = request.uri.path;
    if (path == '/component.html' && _page != null) {
      response.headers.contentType = .html;
      response.add(_page!);
    } else {
      final file = File(p.join('web', p.normalize(path.substring(1))));
      if (file.existsSync()) {
        final type = _contentTypes[p.extension(file.path)];
        if (type != null) {
          response.headers.set(HttpHeaders.contentTypeHeader, type);
        }
        response.add(file.readAsBytesSync());
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    }
    response.close();
  }

  static const _contentTypes = {
    '.css': 'text/css',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.woff2': 'font/woff2',
  };

  /// Screenshots [html] at [width]×[height]. With [transparent], the page has
  /// no background and the PNG keeps its alpha channel.
  Future<Uint8List> _shoot({
    required String html,
    required int width,
    required int height,
    bool transparent = false,
  }) async {
    final page = await _browser.newPage();
    try {
      await page.setViewport(.new(width: width, height: height));
      await page.setContent(
        '<!doctype html><style>html,body{margin:0;background:'
        '${transparent ? 'transparent' : Palette.black.hex}}'
        'svg{display:block}</style>'
        '$html',
      );
      return await page.screenshot(
        clip: .new(0, 0, width, height),
        omitBackground: transparent,
      );
    } finally {
      await page.close();
    }
  }
}
