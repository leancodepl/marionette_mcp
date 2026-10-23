import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/button.dart';
import 'package:marionette_website/components/copy_button.dart';
import 'package:marionette_website/components/icons.dart';
import 'package:marionette_website/components/pill.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/highlight.dart';
import 'package:marionette_website/site.dart';
import 'package:marionette_website/styles.dart';

part 'hero.scopes.dart';

@scopedCss
class Hero extends StatelessComponent {
  const Hero({required this.version, required this.loop, super.key});

  final String version;
  final LoopDemo loop;

  static const _class = _$HeroScope;

  static final _root = _class.root;
  static final _grid = _class('grid');
  static final _copy = _class('copy');
  static final _install = _class('install');
  static final _session = _class('session');
  static final _bubble = _class('bubble');
  static final _who = _class('who');
  static final _prompt = _class('prompt');
  static final _calls = _class('calls');
  static final _callsHead = _class('calls-head');
  static final _chips = _class('chips');
  static final _verdict = _class('verdict');

  // Also drawn by the social card, which restyles them for its canvas.

  /// The accent glow and diagonal lines behind the hero.
  static final bg = _class('bg');

  /// The row of pills above the heading.
  static final badges = _class('badges');

  /// The paragraph under the heading.
  static final lead = _class('lead');

  /// The prompt-style box around the install command.
  static final installCommand = _class('install-command');

  /// A row of call-to-action buttons, also closing the footer.
  static final actions = _class('actions');

  /// Centers [actions].
  static final center = _class('center');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        position: const .relative(),
        padding: .only(
          top: const .expression('clamp(3.5rem, 8vw, 6rem)'),
          bottom: 3.5.rem,
        ),
        overflow: .hidden,
        raw: {'isolation': 'isolate'},
      ),
      css('& h1').styles(
        fontSize: const .expression('clamp(2.4rem, 5.2vw, 4rem)'),
        fontWeight: .w700,
        letterSpacing: (-0.035).em,
        lineHeight: const .expression('1.04'),
      ),
    ]),
    css(bg.selector).styles(
      position: const .absolute(),
      zIndex: const .new(-1),
      raw: {
        'inset': '0',
        'background':
            'radial-gradient(55% 45% at 75% 20%, ${accentAlpha(0.12).value}, '
            'transparent 65%), '
            'radial-gradient(40% 40% at 8% 92%, ${accentAlpha(0.05).value}, '
            'transparent 60%), '
            'repeating-linear-gradient(-58deg, transparent 0 148px, '
            '${accentAlpha(0.08).value} 148px 149px)',
        'mask-image': 'linear-gradient(to bottom, #000 30%, transparent 100%)',
        '-webkit-mask-image':
            'linear-gradient(to bottom, #000 30%, transparent 100%)',
      },
    ),
    css(_grid.selector, [
      css('&').styles(display: .grid, alignItems: .center, gap: .all(3.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 1000.px), [
        css('&').styles(raw: {'grid-template-columns': '1.1fr 1fr'}),
      ]),
    ]),
    css(_copy.selector, [shrinkableChildren()]),
    css(badges.selector).styles(
      display: .flex,
      margin: .only(bottom: 1.5.rem),
      flexWrap: .wrap,
      gap: .all(0.5.rem),
    ),
    css(lead.selector).styles(
      maxWidth: 38.rem,
      margin: .only(top: 1.5.rem),
      color: text2Color,
      fontSize: const .expression('clamp(1.1rem, 1.6vw, 1.25rem)'),
    ),
    css(_install.selector).styles(margin: .only(top: 2.rem)),
    css(installCommand.selector, [
      css('&').styles(
        display: .flex,
        maxWidth: 34.rem,
        padding: .only(
          top: 0.5.rem,
          right: 0.5.rem,
          bottom: 0.5.rem,
          left: 1.rem,
        ),
        border: hairline(border2Color),
        radius: const .circular(radius),
        alignItems: .center,
        gap: .all(0.75.rem),
        backgroundColor: surfaceColor,
        raw: {'box-shadow': shadow},
      ),
      css('& code').styles(
        minWidth: .zero,
        overflow: const .only(x: .auto),
        fontSize: 0.95.rem,
        whiteSpace: .noWrap,
        raw: {'flex': '1'},
      ),
      css.media(.all(maxWidth: 540.px), [
        css('&').styles(flexWrap: .wrap),
        css('& code').styles(order: -1, raw: {'flex-basis': '100%'}),
        css('& ${Highlight.prompt.selector}').styles(display: .none),
      ]),
    ]),
    css(actions.selector, [
      css('&').styles(
        display: .flex,
        margin: .only(top: 1.75.rem),
        flexWrap: .wrap,
        gap: .all(0.75.rem),
      ),
      css('&${center.selector}').styles(justifyContent: .center),
    ]),
    // The session at a glance: what goes in, what the agent does, what comes
    // back. The replay below the hero plays the same run call by call.
    css(_session.selector)
        .styles(display: .grid, minWidth: .zero, gap: .all(0.9.rem)),
    css(_bubble.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 1.1.rem, horizontal: 1.25.rem),
        border: hairline(borderColor),
        radius: const .circular(radius),
        backgroundColor: surfaceColor,
        raw: {'box-shadow': shadow},
      ),
    ]),
    css(_who.selector).styles(
      display: .flex,
      margin: .only(bottom: 0.6.rem),
      alignItems: .center,
      gap: .all(0.5.rem),
      color: mutedColor,
      fontFamily: fontMono,
      fontSize: 0.72.rem,
      fontWeight: .w600,
      textTransform: .upperCase,
      letterSpacing: 0.08.em,
    ),
    css(_prompt.selector).styles(color: textColor, fontSize: 1.02.rem),
    css(_calls.selector).styles(
      padding: .symmetric(vertical: 0.2.rem, horizontal: 1.25.rem),
      border: .only(
        left: .new(color: accentColor, width: 2.px),
      ),
      raw: {'margin-left': '1.25rem'},
    ),
    css(_callsHead.selector).styles(
      margin: .only(bottom: 0.6.rem),
      color: mutedColor,
      fontSize: 0.85.rem,
    ),
    css(_chips.selector, [
      css('&').styles(display: .flex, flexWrap: .wrap, gap: .all(0.35.rem)),
      css('& code').styles(
        padding: .symmetric(vertical: 0.15.rem, horizontal: 0.45.rem),
        border: hairline(borderColor),
        radius: .circular(6.px),
        color: text2Color,
        fontSize: 0.74.rem,
        backgroundColor: surfaceColor,
      ),
    ]),
    css(_verdict.selector, [
      css('&').styles(
        margin: .zero,
        color: text2Color,
        fontFamily: fontMono,
        fontSize: 0.78.rem,
        lineHeight: const .expression('1.7'),
        whiteSpace: .preWrap,
        raw: {'overflow-wrap': 'anywhere'},
      ),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final tools = <String>[];
    for (final beat in loop.beats) {
      if (!tools.contains(beat.tool)) {
        tools.add(beat.tool);
      }
    }
    return section(
      id: 'top',
      classes: _root.name,
      attributes: const {'aria-labelledby': 'hero-heading'},
      [
        div(
          classes: bg.name,
          attributes: const {'aria-hidden': 'true'},
          const [],
        ),
        div(classes: (Utility.container + _grid).name, [
          div(classes: _copy.name, [
            heroBadges(primary: 'v$version'),
            heroHeading(id: 'hero-heading'),
            p(classes: lead.name, const [.text(heroLead)]),
            div(classes: _install.name, [installCommandBox()]),
            div(classes: actions.name, [
              Button(href: '/docs/', [
                Icon.book.build(size: 18),
                const .text('Get started'),
              ]),
              Button(href: repoUrl, variant: .secondary, external: true, [
                Icon.github.build(size: 18),
                const .text('GitHub'),
              ]),
              Button(href: pubUrl, variant: .secondary, external: true, [
                const .text('pub.dev'),
                Icon.external.build(size: 18),
              ]),
            ]),
          ]),
          div(
            classes: _session.name,
            attributes: const {'aria-label': 'One recorded session'},
            [
              div(classes: _bubble.name, [
                p(classes: _who.name, const [.text('You')]),
                p(classes: _prompt.name, [.text(loop.prompt)]),
              ]),
              div(classes: _calls.name, [
                p(classes: _callsHead.name, [
                  .text(
                    'The agent drives the app through Marionette: '
                    '${loop.beats.length} tool calls.',
                  ),
                ]),
                p(classes: _chips.name, [
                  for (final tool in tools) code([.text(tool)]),
                ]),
              ]),
              div(classes: _bubble.name, [
                p(classes: _who.name, const [.text('Back to you')]),
                pre(classes: _verdict.name, [.text(loop.verdict)]),
              ]),
            ],
          ),
        ]),
      ],
    );
  }
}

/// The pills above the hero heading. [primary] is the accented one linking to
/// pub.dev: the version on the page, a label on the social card so the card
/// does not change with every release.
Component heroBadges({required String primary}) =>
    p(classes: Hero.badges.name, [
      Pill(primary, href: pubUrl, accent: true),
      const Pill('Flutter 3.27+'),
      const Pill('MCP + CLI'),
      const Pill('Apache-2.0'),
    ]);

/// The one-line pitch, shared by the page and the social card.
Component heroHeading({String? id}) => h1(id: id, [
  const .text("Your agent's "),
  span(classes: Utility.accent.name, const [.text('hands and eyes')]),
  const .text(' on a running Flutter app.'),
]);

/// The paragraph under the heading, shared by the page and the social card.
const heroLead =
    'If you know Playwright MCP, this is that for Flutter. Your coding agent '
    'connects to the app you run in debug mode, looks at the screen, taps, '
    'types, reads the logs and checks its own work, instead of guessing from '
    'the code.';

/// The install command in a prompt-style box. The copy button is a client
/// island, so the social card leaves it out.
Component installCommandBox({bool copyButton = true}) =>
    div(classes: Hero.installCommand.name, [
      span(
        classes: Highlight.prompt.name,
        attributes: const {'aria-hidden': 'true'},
        const [.text(r'$')],
      ),
      const code([.text(installCommand)]),
      if (copyButton) const CopyButton(text: installCommand, label: 'Copy'),
    ]);
