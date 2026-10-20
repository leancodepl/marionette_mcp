import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/copy_button.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/styles.dart';

part 'docs_widgets.scopes.dart';

/// One box of a [Flow].
class FlowNode {
  const FlowNode(this.title, this.detail, {this.accent = false});

  final String title;

  /// Backticks mark inline code.
  final String detail;
  final bool accent;
}

/// A left-to-right chain of boxes joined by labelled links; it stacks on
/// narrow screens.
@scopedCss
class Flow extends StatelessComponent {
  const Flow({required this.nodes, required this.links, super.key});

  final List<FlowNode> nodes;

  /// What travels between two neighbouring nodes, one fewer than [nodes].
  final List<String> links;

  static const _class = _$FlowScope;

  static final _root = _class.root;
  static final _node = _class('node');
  static final _accent = _class('accent');
  static final _link = _class('link');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(display: .grid, alignItems: .stretch, gap: .all(0.5.rem)),
      css.media(.all(minWidth: 820.px), [
        css('&').styles(
          alignItems: .center,
          raw: {'grid-auto-flow': 'column', 'grid-auto-columns': 'auto'},
        ),
      ]),
    ]),
    css(_node.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 0.85.rem, horizontal: 1.rem),
        border: hairline(border2Color),
        radius: const .circular(radiusSm),
        backgroundColor: surfaceColor,
      ),
      css('& strong')
          .styles(display: .block, color: textColor, fontSize: 0.95.rem),
      css('& p').styles(
        margin: .only(top: 0.25.rem),
        color: mutedColor,
        fontSize: 0.83.rem,
        lineHeight: const .expression('1.45'),
      ),
    ]),
    css(_accent.selector).styles(
      backgroundColor: accentSoftColor,
      raw: {'border-color': accentAlpha(0.45).value},
    ),
    css(_link.selector, [
      css('&').styles(
        color: accentColor,
        textAlign: .center,
        fontFamily: fontMono,
        fontSize: 0.72.rem,
        whiteSpace: .noWrap,
      ),
      css('&::after').styles(content: '↓', display: .block, fontSize: 1.rem),
      css.media(.all(minWidth: 820.px), [css('&::after').styles(content: '⇄')]),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: _root.name, [
      for (final (i, node) in nodes.indexed) ...[
        if (i > 0) span(classes: _link.name, [.text(links[i - 1])]),
        div(classes: (node.accent ? _node + _accent : _node).name, [
          strong([.text(node.title)]),
          p(rich(node.detail)),
        ]),
      ],
    ]);
  }
}

/// A prompt worth copying: what it is for, the prompt itself, and what comes
/// back.
class PromptExample {
  const PromptExample({
    required this.id,
    required this.intent,
    required this.prompt,
    required this.outcome,
  });

  final String id;
  final String intent;
  final String prompt;

  /// Backticks mark inline code.
  final String outcome;
}

/// A grid of [PromptExample] cards with copyable prompts.
@scopedCss
class PromptCards extends StatelessComponent {
  const PromptCards(this.examples, {super.key});

  final List<PromptExample> examples;

  static const _class = _$PromptCardsScope;

  static final _grid = _class('grid');
  static final _card = _class('card');
  static final _intent = _class('intent');
  static final _prompt = _class('prompt');
  static final _outcome = _class('outcome');

  @css
  static List<StyleRule> get styles => [
    css(_grid.selector, [
      css('&').styles(display: .grid, gap: .all(1.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 760.px), [
        css('&').styles(raw: {'grid-template-columns': '1fr 1fr'}),
      ]),
    ]),
    css(_card.selector).styles(
      display: .flex,
      padding: .all(1.2.rem),
      border: hairline(borderColor),
      radius: const .circular(radius),
      flexDirection: .column,
      gap: .all(0.75.rem),
      backgroundColor: surfaceColor,
    ),
    css(_intent.selector, [
      css('&').styles(
        display: .flex,
        justifyContent: .spaceBetween,
        alignItems: .center,
        gap: .all(0.5.rem),
        color: textColor,
        fontSize: 1.02.rem,
        fontWeight: .w600,
      ),
    ]),
    css(_prompt.selector).styles(
      padding: .symmetric(vertical: 0.75.rem, horizontal: 0.9.rem),
      margin: .zero,
      border: .only(
        left: .new(color: accentColor, width: 2.px),
      ),
      radius: .circular(4.px),
      color: text2Color,
      fontSize: 0.93.rem,
      fontStyle: .italic,
      backgroundColor: bgColor,
    ),
    css(_outcome.selector).styles(color: mutedColor, fontSize: 0.9.rem),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: _grid.name, [
      for (final example in examples)
        article(id: example.id, classes: _card.name, [
          div(classes: _intent.name, [
            span([.text(example.intent)]),
            CopyButton(text: example.prompt),
          ]),
          blockquote(classes: _prompt.name, [.text(example.prompt)]),
          p(classes: _outcome.name, rich(example.outcome)),
        ]),
    ]);
  }
}
