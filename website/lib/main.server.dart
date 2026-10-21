/// Server entrypoint: runs once during `jaspr build` to pre-render every route.
library;

import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:marionette_website/app.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/highlight.dart';
import 'package:marionette_website/main.server.options.dart';
import 'package:marionette_website/seo.dart';
import 'package:marionette_website/site.dart';

Future<void> main() async {
  Jaspr.initializeApp(options: defaultServerOptions);
  await initHighlighting();

  final version = _marionetteVersion();
  final loop = LoopDemo.fromJson(_readDemo('loop.json'));
  final xray = XrayDemo.fromJson(_readDemo('xray.json'));

  runApp(
    Document(
      lang: 'en',
      base: basePath,
      meta: siteMeta,
      head: siteHead(version: version),
      body: App(version: version, loop: loop, xray: xray),
    ),
  );
}

/// Where the recorded demo data lives. A build can point it elsewhere with
/// `--dart-define=DEMO_DIR=…`.
const _demoDir = String.fromEnvironment('DEMO_DIR', defaultValue: 'demo');

Map<String, Object?> _readDemo(String name) =>
    jsonDecode(File('$_demoDir/$name').readAsStringSync())
        as Map<String, Object?>;

/// The Marionette version, read from the `marionette_mcp` pubspec so the site
/// can never announce a stale number. Every Marionette package shares it.
String _marionetteVersion() {
  for (final candidate in [
    '../packages/marionette_mcp/pubspec.yaml',
    'packages/marionette_mcp/pubspec.yaml',
  ]) {
    final file = File(candidate);
    if (!file.existsSync()) {
      continue;
    }
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(file.readAsStringSync());
    if (match != null) {
      return match[1]!;
    }
  }
  throw StateError(
    'No packages/marionette_mcp/pubspec.yaml found; build from the repository.',
  );
}
