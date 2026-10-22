import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/button.dart';
import 'package:marionette_website/components/hero.dart';
import 'package:marionette_website/components/icons.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/site.dart';
import 'package:marionette_website/styles.dart';

part 'footer.scopes.dart';

@scopedCss
class SiteFooter extends StatelessComponent {
  const SiteFooter({required this.version, super.key});

  final String version;

  static const _class = _$SiteFooterScope;

  static final _root = _class.root;
  static final _cta = _class('cta');
  static final _ctaInner = _class('cta-inner');
  static final _grid = _class('grid');
  static final _brand = _class('brand');
  static final _bottom = _class('bottom');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(
      border: .only(top: hairlineSide(borderColor)),
      backgroundColor: bg2Color,
    ),
    css(_cta.selector, [
      css('&').styles(
        padding: const .symmetric(
          vertical: .expression('clamp(4rem, 8vw, 6rem)'),
          horizontal: .zero,
        ),
        border: .only(bottom: hairlineSide(borderColor)),
        raw: {
          'background':
              'radial-gradient(50% 60% at 50% 100%, '
              '${accentAlpha(0.12).value}, transparent 70%), var(--bg-2)',
        },
      ),
      css('& h2')
          .styles(fontSize: const .expression('clamp(1.9rem, 3.6vw, 2.75rem)')),
      css('& p').styles(
        margin: .only(top: 1.rem),
        color: text2Color,
        fontSize: 1.1.rem,
      ),
    ]),
    css(_ctaInner.selector).styles(maxWidth: 40.rem, textAlign: .center),
    css(_grid.selector, [
      css('&').styles(
        display: .grid,
        padding: .symmetric(vertical: 3.5.rem, horizontal: .zero),
        gap: .all(2.5.rem),
      ),
      css('& h3').styles(
        margin: .only(bottom: 0.9.rem),
        color: mutedColor,
        fontFamily: fontMono,
        fontSize: 0.75.rem,
        fontWeight: .w600,
        textTransform: .upperCase,
        letterSpacing: 0.08.em,
      ),
      css('& ul').styles(display: .grid, gap: .all(0.5.rem)),
      css('& li a', [
        css('&').styles(color: text2Color),
        css('&:hover').styles(color: accentColor),
      ]),
      css.media(.all(minWidth: 760.px), [
        css('&').styles(raw: {'grid-template-columns': '1fr 1fr'}),
      ]),
      css.media(.all(minWidth: 1000.px), [
        css('&').styles(raw: {'grid-template-columns': '1.6fr 1fr 1fr 1.4fr'}),
      ]),
    ]),
    css('${_brand.selector} p').styles(
      maxWidth: 24.rem,
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 0.95.rem,
    ),
    css(_bottom.selector).styles(
      display: .flex,
      padding: .only(top: 1.5.rem, bottom: 2.rem),
      border: .only(top: hairlineSide(borderColor)),
      flexWrap: .wrap,
      justifyContent: .spaceBetween,
      gap: .all(0.75.rem),
      color: mutedColor,
      fontSize: 0.85.rem,
    ),
    css('${_bottom.selector} a, ${_brand.selector} p a').styles(
      color: text2Color,
      textDecoration: underlined,
      raw: {'text-underline-offset': '0.15em'},
    ),
  ];

  @override
  Component build(BuildContext context) {
    return footer(classes: _root.name, [
      section(
        classes: _cta.name,
        attributes: const {'aria-labelledby': 'cta-heading'},
        [
          div(classes: (Utility.container + _ctaInner).name, [
            const h2(id: 'cta-heading', [.text("Run it. Don't guess.")]),
            const p([
              .text(
                'Give your agent a running app and let it check its own work.',
              ),
            ]),
            div(classes: (Hero.actions + Hero.center).name, [
              Button(href: '/docs', [
                Icon.book.build(size: 18),
                const .text('Get started'),
              ]),
              Button(href: repoUrl, variant: .secondary, external: true, [
                Icon.github.build(size: 18),
                const .text('GitHub'),
              ]),
            ]),
          ]),
        ],
      ),
      div(classes: (Utility.container + _grid).name, [
        div(classes: _brand.name, [
          logo(),
          p([
            const .text(
              "Your agent's hands and eyes on a running Flutter app. ",
            ),
            externalLink(changelogUrl, [.text('v$version')]),
            const .text(', Apache-2.0.'),
          ]),
        ]),
        nav(
          attributes: const {'aria-label': 'Project'},
          [
            const h3([.text('Project')]),
            ul([
              li([
                externalLink(pubUrl, [const .text('marionette_flutter')]),
              ]),
              li([
                externalLink(pubMcpUrl, [const .text('marionette_mcp')]),
              ]),
              li([
                externalLink(pubCliUrl, [const .text('marionette_cli')]),
              ]),
              li([
                externalLink(repoUrl, [const .text('GitHub')]),
              ]),
              li([
                externalLink(changelogUrl, [const .text('Changelog')]),
              ]),
              li([
                externalLink(issuesUrl, [const .text('Issues')]),
              ]),
            ]),
          ],
        ),
        const nav(
          attributes: {'aria-label': 'Docs'},
          [
            h3([.text('Docs')]),
            ul([
              li([
                a(href: '/docs', [.text('Start')]),
              ]),
              li([
                a(href: '/docs/concepts', [.text('Concepts')]),
              ]),
              li([
                a(href: '/docs/configure', [.text('Configure')]),
              ]),
              li([
                a(href: '/docs/drive', [.text('Drive')]),
              ]),
              li([
                a(href: '/docs/native', [.text('Native lane')]),
              ]),
              li([
                a(href: '/docs/reports', [.text('Reports')]),
              ]),
            ]),
          ],
        ),
        nav(
          attributes: const {'aria-label': 'LeanCode'},
          [
            const h3([.text('LeanCode')]),
            ul([
              li([
                externalLink(leancodeUrl, [const .text('leancode.co')]),
              ]),
              li([
                externalLink(patrolUrl, [const .text('Patrol')]),
              ]),
              li([
                externalLink(leancodePackagesUrl, [
                  const .text('More packages'),
                ]),
              ]),
              li([
                externalLink(leancodeEstimateUrl, [
                  const .text('Hire our team'),
                ]),
              ]),
            ]),
          ],
        ),
      ]),
      div(classes: (Utility.container + _bottom).name, [
        p([
          const .text('© 2026 '),
          externalLink(leancodeUrl, [const .text('LeanCode')]),
          const .text('. Apache License 2.0.'),
        ]),
        p([
          const .text('Built with '),
          externalLink('https://jaspr.site', [const .text('Jaspr')]),
          const .text('.'),
        ]),
      ]),
    ]);
  }
}
