import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/docs_toc.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/components/shell.dart';
import 'package:marionette_website/seo.dart';
import 'package:marionette_website/site.dart';
import 'package:marionette_website/styles.dart';

part 'docs_layout.scopes.dart';

/// The frame of every docs page: the sidebar with the five pages and the
/// current page's sections, the page heading, its sections, and links to the
/// previous and next page.
@scopedCss
class DocsLayout extends StatelessComponent {
  const DocsLayout({
    required this.page,
    required this.version,
    required this.title,
    required this.description,
    required this.lead,
    required this.toc,
    required this.children,
    this.structuredData = const [],
    super.key,
  });

  final SitePage page;
  final String version;

  /// The page's `<h1>`.
  final String title;

  /// The meta description.
  final String description;

  /// The paragraph under the heading. Backticks mark inline code.
  final String lead;

  /// The page's sections as `(id, label)`, in page order.
  final List<(String, String)> toc;
  final List<Component> children;
  final List<Map<String, Object?>> structuredData;

  static const _class = _$DocsLayoutScope;

  static final _docs = _class('docs');
  static final _side = _class('side');
  static final _pages = _class('pages');
  static final _current = _class('current');
  static final _sections = _class('sections');
  static final _sideFoot = _class('side-foot');
  static final _body = _class('body');
  static final _head = _class('head');
  static final _pager = _class('pager');
  static final _next = _class('next');

  /// Where the sidebar sits beside the text, and where it collapses into a
  /// row of page links above it.
  static final _wide = MediaQuery.all(minWidth: 960.px);
  static final _narrow = MediaQuery.all(maxWidth: 959.px);

  @css
  static List<StyleRule> get styles => [
    css(_docs.selector, [
      css('&').styles(
        display: .grid,
        padding: const .only(
          top: .expression('clamp(2rem, 5vw, 3.5rem)'),
          bottom: .expression('clamp(3rem, 8vw, 6rem)'),
        ),
        gap: .all(2.5.rem),
      ),
      shrinkableChildren(),
      css.media(_wide, [
        css('&').styles(raw: {'grid-template-columns': '230px minmax(0, 1fr)'}),
      ]),
    ]),
    css(_side.selector, [
      css.media(_wide, [
        css('&').styles(
          position: const .sticky(
            top: .expression('calc(var(--header-h) + 2rem)'),
          ),
          maxHeight: const .expression('calc(100vh - var(--header-h) - 3rem)'),
          overflow: const .only(y: .auto),
          alignSelf: .start,
          raw: {'scrollbar-width': 'thin'},
        ),
      ]),
      css.media(_narrow, [
        css('& ${Prose.eyebrow.selector}').styles(display: .none),
      ]),
    ]),
    css(_pages.selector, [
      css('&').styles(display: .grid, gap: .all(0.1.rem)),
      css.media(_narrow, [
        css('&').styles(display: .flex, flexWrap: .wrap, gap: .all(0.4.rem)),
      ]),
      css('& > li > a', [
        css('&').styles(
          display: .flex,
          padding: .symmetric(vertical: 0.45.rem, horizontal: 0.75.rem),
          radius: const .circular(radiusSm),
          alignItems: .center,
          gap: .all(0.6.rem),
          color: text2Color,
          fontWeight: .w500,
        ),
        css('&:hover').styles(color: textColor, backgroundColor: surfaceColor),
        css(
          '& span',
        ).styles(color: mutedColor, fontFamily: fontMono, fontSize: 0.75.rem),
        css.media(_narrow, [
          css('&').styles(
            padding: .symmetric(vertical: 0.35.rem, horizontal: 0.8.rem),
            border: hairline(border2Color),
            radius: .circular(999.px),
            fontSize: 0.9.rem,
          ),
        ]),
      ]),
      css('& > li${_current.selector} > a', [
        css('&').styles(color: textColor, backgroundColor: surfaceColor),
        css('& span').styles(color: accentColor),
        css.media(_narrow, [
          css('&').styles(
            color: accentInkColor,
            backgroundColor: accentColor,
            raw: {'border-color': 'var(--accent)'},
          ),
          css('& span').styles(color: accentInkColor),
        ]),
      ]),
    ]),
    // The current page's sections, under its entry in the sidebar.
    css(_sections.selector, [
      css('& ul').styles(
        display: .grid,
        margin: .only(top: 0.3.rem, bottom: 0.6.rem, left: 1.1.rem),
        border: .only(left: hairlineSide(borderColor)),
        gap: .all(0.05.rem),
      ),
      css('& li a', [
        css('&').styles(
          display: .block,
          padding: .symmetric(vertical: 0.3.rem, horizontal: 0.85.rem),
          margin: .only(left: (-1).px),
          border: .only(
            left: .new(color: const .new('transparent'), width: 2.px),
          ),
          color: mutedColor,
          fontSize: 0.88.rem,
        ),
        css(
          '&:hover, &${DocsToc.active.selector}',
        ).styles(color: textColor, raw: {'border-left-color': 'var(--accent)'}),
      ]),
      css.media(_narrow, [css('&').styles(display: .none)]),
    ]),
    css(_sideFoot.selector, [
      css('&').styles(
        padding: .only(top: 1.rem),
        margin: .only(top: 1.rem),
        border: .only(top: hairlineSide(borderColor)),
        color: mutedColor,
        fontSize: 0.85.rem,
      ),
      css('& a').styles(
        color: accentColor,
        textDecoration: underlined,
        raw: {'text-underline-offset': '0.15em'},
      ),
      css.media(_narrow, [css('&').styles(display: .none)]),
    ]),
    css(_body.selector).styles(maxWidth: 52.rem),
    css(_head.selector, [
      css('& h1').styles(
        fontSize: const .expression('clamp(2.2rem, 4vw, 3rem)'),
        fontWeight: .w700,
        letterSpacing: (-0.03).em,
      ),
      css('& ${Prose.lead.selector}').styles(margin: .only(top: 1.rem)),
    ]),
    css(_pager.selector, [
      css('&').styles(
        display: .grid,
        padding: .only(top: 2.rem),
        margin: .only(top: 3.5.rem),
        border: .only(top: hairlineSide(borderColor)),
        gap: .all(1.rem),
        raw: {'grid-template-columns': '1fr 1fr'},
      ),
      css('& a', [
        css('&').styles(
          display: .grid,
          padding: .symmetric(vertical: 0.9.rem, horizontal: 1.1.rem),
          border: hairline(borderColor),
          radius: const .circular(radius),
          gap: .all(0.2.rem),
          backgroundColor: surfaceColor,
        ),
        css('&:hover').styles(raw: {'border-color': 'var(--accent)'}),
        css('& span').styles(color: mutedColor, fontSize: 0.8.rem),
        css('& strong').styles(color: textColor, fontWeight: .w600),
      ]),
    ]),
    css(_next.selector).styles(textAlign: .right, raw: {'grid-column': '2'}),
  ];

  @override
  Component build(BuildContext context) {
    final index = SitePage.docs.indexOf(page);
    final previous = index > 0 ? SitePage.docs[index - 1] : null;
    final next = index < SitePage.docs.length - 1
        ? SitePage.docs[index + 1]
        : null;
    return PageShell(
      page: page,
      version: version,
      children: [
        pageHead(
          title: page == .start ? 'Docs — $siteName' : '$title — $siteName',
          description: description,
          path: page.path.substring(1),
          structuredData: structuredData,
        ),
        div(classes: (Utility.container + _docs).name, [
          nav(
            classes: _side.name,
            attributes: const {'aria-label': 'Docs'},
            [
              p(classes: Prose.eyebrow.name, const [.text('Docs')]),
              ol(classes: _pages.name, [
                for (final (i, docsPage) in SitePage.docs.indexed)
                  li(classes: docsPage == page ? _current.name : null, [
                    a(
                      href: docsPage.path,
                      attributes: docsPage == page
                          ? const {'aria-current': 'page'}
                          : null,
                      [
                        span([.text('0${i + 1}')]),
                        .text(docsPage.title),
                      ],
                    ),
                    if (docsPage == page)
                      div(classes: _sections.name, [
                        DocsToc(
                          path: page.path,
                          ids: [for (final (id, _) in toc) id],
                          labels: [for (final (_, label) in toc) label],
                        ),
                      ]),
                  ]),
              ]),
              p(classes: _sideFoot.name, [
                const .text('The agent-facing reference is the '),
                externalLink(skillUrl, [const .text('Agent Skill')]),
                const .text(' in the package.'),
              ]),
            ],
          ),
          article(classes: _body.name, [
            header(classes: _head.name, [
              h1([.text(title)]),
              p(classes: Prose.lead.name, rich(lead)),
            ]),
            ...children,
            nav(
              classes: _pager.name,
              attributes: const {'aria-label': 'Previous and next page'},
              [
                if (previous != null)
                  a(href: previous.path, [
                    const span([.text('← Previous')]),
                    strong([.text(previous.title)]),
                  ]),
                if (next != null)
                  a(href: next.path, classes: _next.name, [
                    const span([.text('Next →')]),
                    strong([.text(next.title)]),
                  ]),
              ],
            ),
          ]),
        ]),
      ],
    );
  }
}

/// How a [Callout] is marked.
enum CalloutKind {
  note('Note'),
  tip('Tip'),
  warning('Watch out');

  CalloutKind(this.label);

  final String label;
}

/// A short boxed remark inside a docs section. [text] may quote identifiers
/// in backticks.
@scopedCss
class Callout extends StatelessComponent {
  const Callout(this.text, {this.kind = .note, super.key});

  final String text;
  final CalloutKind kind;

  static const _class = _$CalloutScope;

  static final _root = _class.root;
  static final _warning = _class('warning');
  static final _label = _class('label');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 0.9.rem, horizontal: 1.1.rem),
        border: .only(
          left: .new(color: accentColor, width: 3.px),
        ),
        radius: const .circular(radiusSm),
        color: text2Color,
        fontSize: 0.97.rem,
        backgroundColor: accentSoftColor,
      ),
      css('& p').styles(margin: .zero),
    ]),
    css(_warning.selector).styles(
      raw: {
        'border-left-color': 'var(--danger)',
        'background-color': 'color-mix(in srgb, var(--danger) 7%, transparent)',
      },
    ),
    css(_label.selector).styles(color: textColor, fontWeight: .w600),
  ];

  @override
  Component build(BuildContext context) {
    return aside(
      classes: [_root.name, if (kind == .warning) _warning.name].join(' '),
      [
        p([
          span(classes: _label.name, [.text('${kind.label}. ')]),
          ...rich(text),
        ]),
      ],
    );
  }
}

/// A table in the docs. The first cell of each row is its header; on narrow
/// screens every row becomes a card with the column names as labels.
@scopedCss
class DocTable extends StatelessComponent {
  const DocTable({required this.headers, required this.rows, super.key});

  final List<String> headers;

  /// Each row's cells; backticks mark inline code.
  final List<List<String>> rows;

  static const _class = _$DocTableScope;

  static final _wrap = _class('wrap');
  static final _table = _class('table');

  static final _stacked = MediaQuery.all(maxWidth: 640.px);

  @css
  static List<StyleRule> get styles => [
    css(_wrap.selector).styles(
      border: hairline(borderColor),
      radius: const .circular(radius),
      overflow: const .only(x: .auto),
      backgroundColor: surfaceColor,
    ),
    css(_table.selector, [
      css('&').styles(
        width: 100.percent,
        fontSize: 0.93.rem,
        raw: {'border-collapse': 'collapse'},
      ),
      css('& th, & td').styles(
        padding: .symmetric(vertical: 0.8.rem, horizontal: 1.rem),
        border: .only(bottom: hairlineSide(borderColor)),
        textAlign: .left,
        raw: {'vertical-align': 'top'},
      ),
      css('& thead th').styles(
        color: mutedColor,
        fontFamily: fontMono,
        fontSize: 0.72.rem,
        fontWeight: .w600,
        textTransform: .upperCase,
        letterSpacing: 0.08.em,
        backgroundColor: surface2Color,
      ),
      css('& tbody', [
        css('& tr:last-child th, & tr:last-child td')
            .styles(raw: {'border-bottom': '0'}),
        css('& th').styles(fontWeight: .w500),
      ]),
      css('& td').styles(color: text2Color),
      css.media(_stacked, [
        css('& thead').styles(display: .none),
        css('& tbody, & tr, & th, & td').styles(display: .block),
        css('& tr').styles(
          padding: .symmetric(vertical: 0.9.rem, horizontal: 1.rem),
          border: .only(bottom: hairlineSide(borderColor)),
        ),
        css('& tbody tr:last-child').styles(raw: {'border-bottom': '0'}),
        css('& th, & td').styles(padding: .zero, raw: {'border': '0'}),
        css('& tbody th').styles(margin: .only(bottom: 0.4.rem)),
        css('& td + td').styles(margin: .only(top: 0.4.rem)),
        css('& td[data-label]::before').styles(
          color: mutedColor,
          fontFamily: fontMono,
          fontSize: 0.7.rem,
          fontWeight: .w600,
          textTransform: .upperCase,
          letterSpacing: 0.08.em,
          raw: {'content': "attr(data-label) ': '"},
        ),
      ]),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: _wrap.name, [
      table(classes: _table.name, [
        thead([
          tr([
            for (final header in headers)
              th(attributes: const {'scope': 'col'}, [.text(header)]),
          ]),
        ]),
        tbody([
          for (final row in rows)
            tr([
              th(attributes: const {'scope': 'row'}, rich(row.first)),
              for (final (i, cell) in row.skip(1).indexed)
                td(attributes: {'data-label': headers[i + 1]}, rich(cell)),
            ]),
        ]),
      ]),
    ]);
  }
}
