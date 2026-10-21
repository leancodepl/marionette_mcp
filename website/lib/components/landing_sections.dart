import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/card.dart';
import 'package:marionette_website/components/clients.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/copy_button.dart';
import 'package:marionette_website/components/feature_grid.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/highlight.dart';
import 'package:marionette_website/site.dart';
import 'package:marionette_website/styles.dart';

part 'landing_sections.scopes.dart';

/// The binding snippet every app starts with.
const bindingSnippet = '''
void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MyApp());
}''';

/// The example app's design-system configuration, as it is in the repository.
const designSystemSnippet = '''
MarionetteBinding.ensureInitialized(
  MarionetteConfiguration(
    isInteractiveElement: (element) => switch (element.widget) {
      DsButton() || DsSelect() => true,
      DsTile(:final onTap) => onTap != null,
      _ => false,
    },
    extractText: (element) => switch (element.widget) {
      DsSelect(:final selectedLabel) => selectedLabel,
      _ => null,
    },
  ),
);''';

/// What the agent can do, in four verbs.
class Pillars extends StatelessComponent {
  const Pillars({super.key});

  @override
  Component build(BuildContext context) {
    return const Section(
      id: 'tools',
      eyebrow: 'What the agent can do',
      heading: 'See. Act. Verify. Iterate.',
      lead:
          'A small set of tools, each returning only what the next decision '
          "needs, so the agent's context stays small.",
      children: [
        FeatureGrid(minWidth: 240, [
          Feature(
            .eye,
            'See',
            'List every button, field and label on screen with its key, text '
                'and position, or take a screenshot.',
            tools: ['get_interactive_elements', 'take_screenshots'],
          ),
          Feature(
            .pointer,
            'Act',
            'Tap, type, scroll, swipe, long-press, pinch and press keys, '
                'matched by key, Semantics identifier, text or type.',
            tools: [
              'tap',
              'enter_text',
              'scroll_to',
              'swipe',
              'long_press',
              'press_key',
              'press_back_button',
            ],
          ),
          Feature(
            .verify,
            'Verify',
            "Read the app's logs to confirm the request fired or to catch the "
                'exception. Sweep text scale, bold text and dark mode.',
            tools: ['get_logs', 'set_device_config'],
          ),
          Feature(
            .refresh,
            'Iterate',
            'Change the code, hot reload, and replay the same steps to '
                'confirm the change.',
            tools: ['hot_reload', 'hot_restart'],
          ),
        ]),
      ],
    );
  }
}

/// Session reports: who writes what, and why the record can be trusted.
@scopedCss
class WhatYouGetBack extends StatelessComponent {
  const WhatYouGetBack({super.key});

  static const _class = _$WhatYouGetBackScope;

  static final _grid = _class('grid');
  static final _items = _class('items');
  static final _item = _class('item');
  static final _verdicts = _class('verdicts');

  /// A verdict word, colored by what it means.
  static final verdict = _class('verdict');
  static final pass = _class('pass');
  static final suspect = _class('suspect');
  static final fail = _class('fail');
  static final blocked = _class('blocked');

  @css
  static List<StyleRule> get styles => [
    css(_grid.selector, [
      css('&').styles(display: .grid, alignItems: .start, gap: .all(2.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 900.px), [
        css('&').styles(raw: {'grid-template-columns': '1fr 1fr'}),
      ]),
    ]),
    css(_items.selector).styles(display: .grid, gap: .all(1.rem)),
    css(_item.selector, [
      css('& h3').styles(
        display: .flex,
        alignItems: .center,
        gap: .all(0.5.rem),
        fontFamily: fontMono,
        fontSize: 1.rem,
      ),
      css('& h3 span').styles(
        color: mutedColor,
        fontFamily: fontSans,
        fontSize: 0.85.rem,
        fontWeight: .w400,
      ),
    ]),
    css(_verdicts.selector).styles(
      display: .flex,
      margin: .only(top: 0.8.rem),
      flexWrap: .wrap,
      gap: .all(0.4.rem),
    ),
    css(verdict.selector).styles(
      padding: .symmetric(vertical: 0.2.rem, horizontal: 0.55.rem),
      border: hairline(border2Color),
      radius: .circular(6.px),
      fontFamily: fontMono,
      fontSize: 0.75.rem,
      fontWeight: .w700,
      letterSpacing: 0.04.em,
    ),
    css(pass.selector).styles(
      color: okColor,
      raw: {'border-color': 'color-mix(in srgb, var(--ok) 45%, transparent)'},
    ),
    css(suspect.selector).styles(
      color: const .variable('--tk-annotation'),
      raw: {'border-color': 'color-mix(in srgb, #ffcb6b 45%, transparent)'},
    ),
    css(fail.selector).styles(
      color: dangerColor,
      raw: {
        'border-color': 'color-mix(in srgb, var(--danger) 45%, transparent)',
      },
    ),
    css(blocked.selector).styles(color: mutedColor),
  ];

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'reports',
      eyebrow: 'Session reports',
      heading: 'Every run leaves a record you can check.',
      lead:
          'Turn on `enableSessionReports` and each run gets its own folder. '
          'The server logs every tool call. The agent writes the report and '
          'cites that log.',
      children: [
        div(classes: _grid.name, [
          div(classes: _items.name, [
            Card(classes: _item, const [
              h3([
                .text('steps.md'),
                span([.text('written by the server')]),
              ]),
              p([
                .text(
                  'One line per tool call, appended as it happens. The agent '
                  'cannot skip or embellish a step, and typed secrets are '
                  'redacted.',
                ),
              ]),
            ]),
            Card(classes: _item, [
              const h3([
                .text('report.md'),
                span([.text('written by the agent')]),
              ]),
              p(
                rich(
                  'Written at the end. Every finding cites a step, a log line '
                  'or a screenshot, and the `Tested:` line is counted from '
                  '`steps.md`, not from memory.',
                ),
              ),
            ]),
            Card(classes: _item, [
              const h3([
                .text('the verdict'),
                span([.text('in the chat')]),
              ]),
              const p([
                .text(
                  'One short closing message: what worked, what did not, '
                  'what was not covered, and where the report is.',
                ),
              ]),
              p(classes: _verdicts.name, [
                span(classes: (verdict + pass).name, const [.text('PASS')]),
                span(classes: (verdict + suspect).name, const [
                  .text('SUSPECT'),
                ]),
                span(classes: (verdict + fail).name, const [.text('FAIL')]),
                span(classes: (verdict + blocked).name, const [
                  .text('BLOCKED'),
                ]),
              ]),
            ]),
          ]),
          div([
            const CodeBlock(
              source: _sessionTree,
              language: .console,
              title: '.marionette/sessions/',
              copyText: '',
            ),
            p(classes: Prose.more.name, const [
              a(href: '/docs/reports', [
                .text('How a report is written, with examples →'),
              ]),
            ]),
          ]),
        ]),
      ],
    );
  }
}

const _sessionTree = '''
profile-email-validation-20261006T1326/
  steps.md        # appended by the server, one line per call
  report.md       # written once, by the agent
  screenshots/
    01.png        # take_screenshots(inline: false)
    02.png''';

/// From nothing to the first prompt.
@scopedCss
class QuickStart extends StatelessComponent {
  const QuickStart({super.key});

  static const _class = _$QuickStartScope;

  static final _steps = _class('steps');
  static final _step = _class('step');
  static final _num = _class('num');
  static final _body = _class('body');

  @css
  static List<StyleRule> get styles => [
    css(_steps.selector).styles(
      display: .grid,
      gap: .all(2.5.rem),
      raw: {'counter-reset': 'step'},
    ),
    css(_step.selector, [
      css('&').styles(display: .grid, gap: .all(1.25.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 900.px), [
        css('&').styles(raw: {'grid-template-columns': '20rem minmax(0, 1fr)'}),
      ]),
      css('& h3').styles(fontSize: 1.25.rem),
      css('& p').styles(
        margin: .only(top: 0.6.rem),
        color: text2Color,
      ),
    ]),
    css(_num.selector).styles(
      display: .inlineGrid,
      width: 2.rem,
      height: 2.rem,
      margin: .only(bottom: 0.9.rem),
      radius: .circular(50.percent),
      color: accentInkColor,
      fontFamily: fontMono,
      fontWeight: .w700,
      backgroundColor: accentColor,
      raw: {'place-items': 'center'},
    ),
    css(_body.selector).styles(display: .grid, gap: .all(1.rem)),
  ];

  Component _step3(int n, String title, String text, List<Component> body) =>
      li(classes: _step.name, [
        div([
          span(classes: _num.name, [.text('$n')]),
          h3([.text(title)]),
          p(rich(text)),
        ]),
        div(classes: _body.name, body),
      ]);

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'start',
      eyebrow: 'Quick start',
      heading: 'Three steps to the first prompt.',
      children: [
        ol(classes: _steps.name, [
          _step3(
            1,
            'Add Marionette to the app',
            'One package, and a binding that only exists in debug builds. '
                'Release builds stay untouched.',
            [
              const CodeBlock(
                source: installCommand,
                language: .shell,
                title: 'terminal',
              ),
              const CodeBlock(
                source: bindingSnippet,
                language: .dart,
                title: 'lib/main.dart',
              ),
            ],
          ),
          _step3(
            2,
            'Give your agent the tools',
            'Pick the bridge you prefer: the MCP server or the `marionette` '
                'CLI. Both see and drive the app, and both write session '
                'reports.',
            [const BridgeOptions()],
          ),
          _step3(
            3,
            'Run the app and ask',
            'Paste the `ws://` URI that `flutter run` prints into the prompt. '
                'Or ask the agent to start the app: it reads the URI from '
                'the output itself.',
            [
              firstPromptTabs(name: 'prompt-landing'),
              p(classes: Prose.more.name, const [
                a(href: '/docs', [.text('The full setup, step by step →')]),
              ]),
            ],
          ),
        ]),
      ],
    );
  }
}

/// The two bridges in one frame, a row each with the same layout, so the
/// page offers a choice instead of a default. The MCP row switches its
/// register line between clients with radio inputs and CSS alone.
@scopedCss
class BridgeOptions extends StatelessComponent {
  const BridgeOptions({super.key});

  static const _class = _$BridgeOptionsScope;

  static final _root = _class.root;
  static final _option = _class('option');
  static final _description = _class('description');
  static final _body = _class('body');
  static final _switch = _class('switch');
  static final _input = _class('input');
  static final _commands = _class('commands');
  static final _variant = _class('variant');
  static final _copy = _class('copy');
  static final _chips = _class('chips');
  static final _chip = _class('chip');
  static final _link = _class('link');
  static final _or = _class('or');

  /// Radio group name; the landing page has one of these.
  static const _group = 'bridge-client';

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(
      border: hairline(borderColor),
      radius: const .circular(radius),
      backgroundColor: surfaceColor,
    ),
    css(_option.selector, [
      css('&').styles(
        display: .grid,
        padding: .symmetric(vertical: 1.25.rem, horizontal: 1.4.rem),
        gap: .all(1.rem),
      ),
      shrinkableChildren(),
      css.media(.all(minWidth: 760.px), [
        css('&').styles(raw: {'grid-template-columns': '11rem minmax(0, 1fr)'}),
      ]),
      css('& h4').styles(margin: .zero, color: textColor, fontSize: 1.05.rem),
    ]),
    css(_description.selector).styles(
      margin: .only(top: 0.35.rem),
      color: text2Color,
      fontSize: 0.9.rem,
    ),
    css(
      _body.selector,
    ).styles(display: .grid, position: const .relative(), gap: .all(0.75.rem)),
    css(_input.selector).styles(
      position: const .absolute(),
      width: 1.px,
      height: 1.px,
      margin: .all((-1).px),
      opacity: 0,
      overflow: .hidden,
      raw: {'clip': 'rect(0 0 0 0)'},
    ),
    css(_commands.selector, [
      // Commands wrap like a terminal, continuations hanging under the
      // command, so a narrow screen never scrolls sideways.
      css('& pre').styles(
        padding: .only(
          top: 0.7.rem,
          right: 3.rem,
          bottom: 0.7.rem,
          left: 0.9.rem,
        ),
        margin: .zero,
        border: hairline(borderColor),
        radius: .circular(10.px),
        color: text2Color,
        fontSize: 0.8125.rem,
        lineHeight: const .expression('1.65'),
        whiteSpace: .preWrap,
        backgroundColor: bgColor,
        raw: {'overflow-wrap': 'anywhere'},
      ),
      css('& ${Highlight.line.selector}').styles(
        display: .inlineBlock,
        width: 100.percent,
        padding: const .only(left: .expression('2ch')),
        textIndent: const .expression('-2ch'),
      ),
    ]),
    css(_variant.selector).styles(position: const .relative()),
    css('${_switch.selector} ${_variant.selector}').styles(display: .none),
    css(_copy.selector).styles(
      position: .absolute(top: 0.4.rem, right: 0.4.rem),
    ),
    css(_chips.selector)
        .styles(display: .flex, flexWrap: .wrap, gap: .all(0.4.rem)),
    css(_chip.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 0.25.rem, horizontal: 0.7.rem),
        border: hairline(borderColor),
        radius: .circular(999.px),
        cursor: .pointer,
        transition: .combine([
          .new('border-color', duration: 150.ms, curve: .ease),
          .new('color', duration: 150.ms, curve: .ease),
        ]),
        color: text2Color,
        fontSize: 0.8.rem,
        fontWeight: .w500,
      ),
      css('&:hover').styles(color: textColor),
    ]),
    // The checked radio shows its register line and marks its chip, by
    // position, as in [Tabs].
    for (var i = 1; i <= mcpClients.length; i++) ...[
      css(
        '${_input.selector}:nth-of-type($i):checked ~ ${_commands.selector} '
        '> ${_variant.selector}:nth-of-type($i)',
      ).styles(display: .block),
      css(
        '${_input.selector}:nth-of-type($i):checked ~ ${_chips.selector} '
        '> ${_chip.selector}:nth-of-type($i)',
      ).styles(
        border: hairline(accentColor),
        color: accentColor,
        raw: {
          'background-color':
              'color-mix(in srgb, var(--accent) 10%, transparent)',
        },
      ),
      css(
        '${_input.selector}:nth-of-type($i):focus-visible ~ '
        '${_chips.selector} > ${_chip.selector}:nth-of-type($i)',
      ).styles(
        outline: .new(
          color: accentColor,
          style: .solid,
          width: .new(2.px),
          offset: 2.px,
        ),
      ),
    ],
    css('${_link.selector} a').styles(
      color: mutedColor,
      fontSize: 0.875.rem,
      textDecoration: underlined,
      raw: {'text-underline-offset': '0.15em'},
    ),
    css('${_link.selector} a:hover').styles(color: accentColor),
    css(_or.selector, [
      css('&').styles(
        display: .flex,
        padding: .symmetric(horizontal: 1.4.rem),
        alignItems: .center,
        gap: .all(0.75.rem),
        color: mutedColor,
        fontFamily: fontMono,
        fontSize: 0.75.rem,
        textTransform: .upperCase,
        letterSpacing: 0.08.em,
      ),
      css('&::before, &::after').styles(
        border: .only(top: hairlineSide(borderColor)),
        raw: {'content': '""', 'flex': '1'},
      ),
    ]),
  ];

  /// One command block: [lines] as shown, [copy] as copied.
  Component _block(List<String> lines, String copy) =>
      div(classes: _variant.name, [
        pre([code(highlight(lines.join('\n'), .console))]),
        span(classes: _copy.name, [CopyButton(text: copy)]),
      ]);

  Component _heading(String name, String description) => div([
    h4([.text(name)]),
    p(classes: _description.name, rich(description)),
  ]);

  Component _mcpRow() {
    final clients = [
      for (final client in mcpClients)
        if (client.inQuickStart) client,
    ];
    return div(classes: _option.name, [
      _heading('MCP server', 'Your agent calls Marionette’s tools.'),
      div(classes: [_body.name, _switch.name].join(' '), [
        for (final (index, client) in clients.indexed)
          input(
            type: .radio,
            name: _group,
            id: '$_group-${client.id}',
            classes: _input.name,
            checked: index == 0 ? true : null,
          ),
        div(classes: _commands.name, [
          for (final client in clients)
            if (client.command case final command?)
              _block([
                '\$ $mcpInstallCommand',
                '\$ $command',
              ], '$mcpInstallCommand\n$command')
            else
              _block([
                '\$ $mcpInstallCommand',
                '# then add to ${client.configFile}:',
                _oneLine(client.config!),
              ], _oneLine(client.config!)),
        ]),
        div(
          classes: _chips.name,
          attributes: const {'role': 'group', 'aria-label': 'AI tool'},
          [
            for (final client in clients)
              label(
                classes: _chip.name,
                attributes: {'for': '$_group-${client.id}'},
                [.text(client.label)],
              ),
          ],
        ),
      ]),
    ]);
  }

  /// A config snippet folded onto one line, so every client's block keeps
  /// the same height.
  static String _oneLine(String json) => json.replaceAll(RegExp(r'\n\s*'), ' ');

  @override
  Component build(BuildContext context) {
    return div(classes: _root.name, [
      _mcpRow(),
      div(
        classes: _or.name,
        attributes: const {'aria-hidden': 'true'},
        const [.text('or')],
      ),
      div(classes: _option.name, [
        _heading('CLI', 'Your agent runs `marionette` commands in its shell.'),
        div(classes: _body.name, [
          div(classes: _commands.name, [
            _block(const ['\$ $cliInstallCommand'], cliInstallCommand),
          ]),
          p(classes: _link.name, const [
            a(href: '/docs/drive#cli', [.text('What the CLI can do →')]),
          ]),
        ]),
      ]),
    ]);
  }
}

/// Custom design systems: the one configuration most apps need.
@scopedCss
class DesignSystem extends StatelessComponent {
  const DesignSystem({super.key});

  static const _class = _$DesignSystemScope;

  static final _grid = _class('grid');

  @css
  static List<StyleRule> get styles => [
    css(_grid.selector, [
      css('&').styles(display: .grid, alignItems: .start, gap: .all(2.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 900.px), [
        css('&').styles(raw: {'grid-template-columns': '1.2fr 1fr'}),
      ]),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'design-system',
      eyebrow: 'Your design system',
      heading: 'Material works as is. Your widgets take one switch.',
      lead:
          "Marionette recognizes Flutter's own buttons, fields and controls "
          'with no configuration. For a custom design system, tell it which '
          'widgets are interactive and where their text lives.',
      children: [
        div(classes: _grid.name, [
          const CodeBlock(
            source: designSystemSnippet,
            language: .dart,
            title: 'example/lib/main.dart',
          ),
          div([
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'An `is` pattern matches every subclass and every generic '
                  'variant, such as `DsSelect<T>`.',
                ),
              ),
              li(
                rich(
                  'Custom-painted content, such as a gauge or a chart, '
                  'becomes readable through `Semantics(label:, value:)`.',
                ),
              ),
              li(
                rich(
                  'No key on a widget? `Semantics(identifier:)` is an equally '
                  'stable selector, and screen readers never announce it.',
                ),
              ),
              li(
                rich(
                  'Logs come from the `logging` or `logger` package, or from '
                  'anything you route into a `PrintLogCollector`.',
                ),
              ),
            ]),
            p(classes: Prose.more.name, const [
              a(href: '/docs/configure', [
                .text('Configure your design system →'),
              ]),
            ]),
          ]),
        ]),
      ],
    );
  }
}

/// Uses beyond a smoke test.
class MoreThanTests extends StatelessComponent {
  const MoreThanTests({super.key});

  @override
  Component build(BuildContext context) {
    return const Section(
      id: 'uses',
      eyebrow: 'Beyond smoke tests',
      heading: 'More than a test runner.',
      children: [
        FeatureGrid([
          Feature(
            .refresh,
            'Reproduce, fix, replay',
            'Follow the steps from a ticket, fix the code, `hot_reload`, and '
                'replay the same steps. The agent shows the fix works instead '
                'of claiming it.',
          ),
          Feature(
            .textSize,
            'Accessibility sweeps',
            '`set_device_config` sets text scale, bold text and dark mode in '
                'the running app. The agent then reads the logs for overflow '
                'errors.',
          ),
          Feature(
            .plug,
            "Your app's own tools",
            'Register an extension, such as “go to a page” or “seed test '
                'data”, and it becomes a named tool with a validated schema.',
            href: '/docs/configure#extensions',
            linkLabel: 'Custom extensions →',
          ),
          Feature(
            .terminal,
            'MCP server or CLI',
            'Two bridges to the same app. Pick the one you and your agent '
                'prefer; both write the same session reports.',
            href: '/docs/concepts#mcp-or-cli',
            linkLabel: 'Compare them →',
          ),
          Feature(
            .sparkle,
            'An Agent Skill in the package',
            '`dart run skills@ get` installs a skill that teaches the agent '
                'to set up your app and drive it well.',
            href: '/docs#skill',
            linkLabel: 'Install the skill →',
          ),
          Feature(
            .file,
            'Evidence for a pull request',
            'Before and after screenshots, a session report, or a short video '
                'from `marionette record-video`.',
          ),
        ]),
      ],
    );
  }
}

/// Marionette next to the Dart and Flutter MCP server and Patrol.
@scopedCss
class WhereItFits extends StatelessComponent {
  const WhereItFits({super.key});

  static const _class = _$WhereItFitsScope;

  static final _grid = _class('grid');
  static final _col = _class('col');
  static final _here = _class('here');
  static final _role = _class('role');

  @css
  static List<StyleRule> get styles => [
    css(_grid.selector, [
      css('&').styles(display: .grid, gap: .all(1.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 900.px), [
        css('&').styles(raw: {'grid-template-columns': 'repeat(3, 1fr)'}),
      ]),
    ]),
    css(_col.selector, [
      css('&')
          .styles(display: .flex, flexDirection: .column, gap: .all(0.6.rem)),
      css('& h3').styles(margin: .zero),
      css('& h3 + p').styles(raw: {'flex': '1'}),
      css('& a').styles(color: accentColor, fontSize: 0.92.rem),
    ]),
    css(_here.selector).styles(raw: {'border-color': accentAlpha(0.45).value}),
    css(_role.selector).styles(
      color: accentColor,
      fontFamily: fontMono,
      fontSize: 0.75.rem,
      fontWeight: .w600,
      textTransform: .upperCase,
      letterSpacing: 0.08.em,
    ),
  ];

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'fit',
      eyebrow: 'Where it fits',
      heading: 'Use it next to the tools you already have.',
      children: [
        div(classes: _grid.name, [
          Card(classes: _col, [
            p(classes: _role.name, const [.text('Build')]),
            const h3([.text('Dart and Flutter MCP server')]),
            const p([
              .text(
                'Searches pub.dev, manages dependencies, analyzes code and '
                'inspects runtime errors while the agent writes the app.',
              ),
            ]),
            externalLink(flutterMcpUrl, [const .text('docs.flutter.dev →')]),
          ]),
          Card(classes: _col + _here, [
            p(classes: _role.name, const [.text('Drive and verify')]),
            const h3([.text('Marionette')]),
            const p([
              .text(
                'Runs the app the agent just changed: looks at the screen, '
                'acts on it, reads the logs, and reports what it saw. Debug '
                'and profile builds.',
              ),
            ]),
            const a(href: '/docs/concepts', [.text('How it works →')]),
          ]),
          Card(classes: _col, [
            p(classes: _role.name, const [.text('Regression suites')]),
            const h3([.text('Patrol')]),
            const p([
              .text(
                'Deterministic end-to-end tests for CI, which pass or fail '
                'the same way on every run. Marionette gestures simulate a '
                'user on a best-effort basis.',
              ),
            ]),
            externalLink(patrolUrl, [const .text('patrol.leancode.co →')]),
          ]),
        ]),
      ],
    );
  }
}
