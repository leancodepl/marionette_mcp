import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/pages/docs/concepts_page.dart';
import 'package:marionette_website/pages/docs/configure_page.dart';
import 'package:marionette_website/pages/docs/drive_page.dart';
import 'package:marionette_website/pages/docs/reports_page.dart';
import 'package:marionette_website/pages/docs/start_page.dart';
import 'package:marionette_website/pages/home_page.dart';

/// The site: the landing page and five docs pages. Every route is rendered to
/// static HTML at build time; only small `@client` islands hydrate.
class App extends StatelessComponent {
  const App({
    required this.version,
    required this.loop,
    required this.xray,
    super.key,
  });

  /// The Marionette version shown across the site.
  final String version;

  /// The recorded session the landing page replays.
  final LoopDemo loop;

  /// The screen the Concepts page takes apart.
  final XrayDemo xray;

  @override
  Component build(BuildContext context) {
    return Router(
      routes: [
        Route(
          path: '/',
          builder: (context, state) => HomePage(version: version, loop: loop),
        ),
        Route(
          path: '/docs',
          builder: (context, state) => StartPage(version: version),
        ),
        Route(
          path: '/docs/concepts',
          builder: (context, state) =>
              ConceptsPage(version: version, xray: xray),
        ),
        Route(
          path: '/docs/configure',
          builder: (context, state) => ConfigurePage(version: version),
        ),
        Route(
          path: '/docs/drive',
          builder: (context, state) => DrivePage(version: version),
        ),
        Route(
          path: '/docs/reports',
          builder: (context, state) =>
              ReportsPage(version: version, loop: loop),
        ),
      ],
    );
  }
}
