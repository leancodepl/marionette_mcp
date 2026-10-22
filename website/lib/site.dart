/// Site-wide constants: where the site lives and where it links to.
library;

import 'package:jaspr/jaspr.dart' show kReleaseMode;

const productionUrl = 'https://marionette.leancode.co';

/// Public URL of the deployed site. Preview deployments override it with
/// `--dart-define=SITE_URL=https://…` at build time.
const siteUrl = String.fromEnvironment('SITE_URL', defaultValue: productionUrl);

/// Whether this build is the live site: a release build (`jaspr build`, or
/// `jaspr serve --release`) for the production URL. Previews, other
/// `SITE_URL`s and plain `jaspr serve` load no analytics, so they never count
/// as visits.
const isProduction = kReleaseMode && siteUrl == productionUrl;

/// [siteUrl] with a guaranteed trailing slash, for canonical and Open Graph
/// URLs.
final canonicalUrl = siteUrl.endsWith('/') ? siteUrl : '$siteUrl/';

/// The `<base href>` derived from [siteUrl], so relative asset paths still
/// resolve if the site is ever served from a sub-path.
final basePath = () {
  final path = Uri.parse(siteUrl).path;
  if (path.isEmpty || path == '/') {
    return '/';
  }
  return path.endsWith('/') ? path : '$path/';
}();

const siteName = 'Marionette';
const tagline = "Your agent's hands and eyes on a running Flutter app";
const description =
    'Marionette connects Claude Code, Cursor, Codex, Gemini CLI, Copilot or '
    'any MCP client to the Flutter app you run in debug mode. The agent sees '
    'the screen, taps, types, scrolls, reads logs, hot reloads and writes a '
    'report of what it did.';

const repoUrl = 'https://github.com/leancodepl/marionette_mcp';
const pubUrl = 'https://pub.dev/packages/marionette_flutter';
const pubMcpUrl = 'https://pub.dev/packages/marionette_mcp';
const pubCliUrl = 'https://pub.dev/packages/marionette_cli';
const pubLoggingUrl = 'https://pub.dev/packages/marionette_logging';
const pubLoggerUrl = 'https://pub.dev/packages/marionette_logger';
const changelogUrl = '$repoUrl/blob/main/CHANGELOG.md';
const issuesUrl = '$repoUrl/issues';
const licenseUrl = '$repoUrl/blob/main/LICENSE';
const exampleUrl = '$repoUrl/tree/main/example';
const skillUrl =
    '$repoUrl/blob/main/packages/marionette_flutter/skills/'
    'marionette-flutter-drive-app/SKILL.md';

const _utm =
    'utm_source=marionette-website&utm_medium=referral&utm_campaign=marionette';
const leancodeUrl = 'https://leancode.co/?$_utm';
const leancodeEstimateUrl = 'https://leancode.co/get-estimate?$_utm';
const leancodePackagesUrl =
    'https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads';
const patrolUrl = 'https://patrol.leancode.co/?$_utm';
const flutterMcpUrl = 'https://docs.flutter.dev/ai/mcp-server';

/// The first command a reader runs: Marionette's half that lives in the app.
const installCommand = 'flutter pub add marionette_flutter';
const mcpInstallCommand = 'dart pub global activate marionette_mcp';
const cliInstallCommand = 'dart pub global activate marionette_cli';
const claudeMcpAddCommand =
    'claude mcp add --transport stdio marionette -- marionette_mcp';
