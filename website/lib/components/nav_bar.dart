import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/icons.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/components/shell.dart';
import 'package:marionette_website/palette.dart';
import 'package:marionette_website/site.dart';
import 'package:marionette_website/styles.dart';

part 'nav_bar.scopes.dart';

/// The site header: the brand on the left, and on the right the three places
/// a visitor can go from any page. Every item is a real link; in-page
/// sections are reached by scrolling.
@scopedCss
class NavBar extends StatelessComponent {
  const NavBar({required this.page, super.key});

  final SitePage page;

  static const _class = _$NavBarScope;

  static final _root = _class.root;
  static final _nav = _class('nav');
  static final _brand = _class('brand');
  static final _links = _class('links');
  static final _active = _class('active');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(
      position: const .sticky(top: .zero),
      zIndex: const .new(50),
      height: headerHeight,
      border: .only(bottom: hairlineSide(borderColor)),
      backdropFilter: .list([const .saturate(1.4), .blur(14.px)]),
      backgroundColor: Palette.black.alpha(0.75),
      raw: {'-webkit-backdrop-filter': 'saturate(140%) blur(14px)'},
    ),
    css(_nav.selector, [
      css('&').styles(
        display: .flex,
        height: 100.percent,
        justifyContent: .spaceBetween,
        alignItems: .center,
        gap: .all(1.rem),
      ),
      css.media(.all(maxWidth: 540.px), [css('&').styles(gap: .all(0.5.rem))]),
    ]),
    css(_brand.selector)
        .styles(display: .inlineFlex, alignItems: .center, color: textColor),
    css(_links.selector, [
      css('&').styles(display: .flex, alignItems: .center, gap: .all(0.25.rem)),
      css('& a', [
        css('&').styles(
          display: .inlineFlex,
          padding: .symmetric(vertical: 0.5.rem, horizontal: 0.85.rem),
          radius: .circular(999.px),
          alignItems: .center,
          gap: .all(0.45.rem),
          color: text2Color,
          fontSize: 0.95.rem,
          fontWeight: .w500,
        ),
        css('& svg').styles(color: mutedColor),
        css('&:hover, &${_active.selector}')
            .styles(color: textColor, backgroundColor: surfaceColor),
        css('&${_active.selector} svg').styles(color: accentColor),
        css.media(.all(maxWidth: 540.px), [
          css('&').styles(
            padding: .symmetric(vertical: 0.5.rem, horizontal: 0.6.rem),
            gap: .all(0.35.rem),
            fontSize: 0.9.rem,
          ),
          css('& svg').styles(display: .none),
          css('&[aria-label] svg').styles(display: .block),
        ]),
      ]),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final onDocs = page.isDocs;
    return header(classes: _root.name, [
      nav(
        classes: (Utility.container + _nav).name,
        attributes: const {'aria-label': 'Primary'},
        [
          a(
            href: '/',
            classes: _brand.name,
            attributes: const {'aria-label': 'Marionette home'},
            [logo()],
          ),
          ul(classes: _links.name, [
            li([
              a(
                href: '/docs',
                classes: onDocs ? _active.name : null,
                attributes: page == .start
                    ? const {'aria-current': 'page'}
                    : null,
                [Icon.book.build(size: 18), const .text('Docs')],
              ),
            ]),
            li([
              externalLink(pubUrl, [
                Icon.external.build(size: 18),
                const .text('pub.dev'),
              ]),
            ]),
            li([
              externalLink(repoUrl, label: 'Marionette on GitHub', [
                Icon.github.build(size: 18),
                span(classes: Utility.hideSm.name, const [.text('GitHub')]),
              ]),
            ]),
          ]),
        ],
      ),
    ]);
  }
}
