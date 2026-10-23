import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/footer.dart';
import 'package:marionette_website/components/nav_bar.dart';
import 'package:marionette_website/styles.dart';

part 'shell.scopes.dart';

/// Which page is being shown; drives the active nav item, the docs sidebar
/// and the page-relative anchors (a bare `#fragment` would resolve against
/// the document's `<base href>`).
enum SitePage {
  home('/', 'Home'),
  start('/docs', 'Start'),
  concepts('/docs/concepts', 'Concepts'),
  configure('/docs/configure', 'Configure'),
  drive('/docs/drive', 'Drive'),
  reports('/docs/reports', 'Reports');

  SitePage(this.path, this.title);

  final String path;

  /// The URL to link to. Netlify serves each page from its directory and
  /// redirects the bare path there with a 301, so links, the canonical URL
  /// and the sitemap all carry the trailing slash.
  String get href => path == '/' ? path : '$path/';

  /// The page's name in the docs sidebar.
  final String title;

  /// The docs pages, in reading order.
  static const docs = [start, concepts, configure, drive, reports];

  bool get isDocs => this != home;
}

/// Skip link, header, `<main>` and footer around a page's content.
@scopedCss
class PageShell extends StatelessComponent {
  const PageShell({
    required this.page,
    required this.version,
    required this.children,
    super.key,
  });

  final SitePage page;
  final String version;
  final List<Component> children;

  static const _class = _$PageShellScope;

  static final _skipLink = _class('skip-link');

  @css
  static List<StyleRule> get styles => [
    css(_skipLink.selector, [
      css('&').styles(
        position: .fixed(top: 12.px, left: 12.px),
        zIndex: const .new(100),
        padding: .symmetric(vertical: 0.6.rem, horizontal: 1.rem),
        radius: const .circular(radiusSm),
        transition: .new('transform', duration: 200.ms, curve: .ease),
        transform: .translate(y: (-200).percent),
        color: accentInkColor,
        fontWeight: .w600,
        backgroundColor: accentColor,
      ),
      css('&:focus').styles(transform: const .translate(y: .zero)),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return .fragment([
      a(href: '${page.href}#main', classes: _skipLink.name, const [
        .text('Skip to content'),
      ]),
      NavBar(page: page),
      main_(id: 'main', children),
      SiteFooter(version: version),
    ]);
  }
}
