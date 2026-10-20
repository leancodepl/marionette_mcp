import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/copy_button.dart';
import 'package:marionette_website/highlight.dart';
import 'package:marionette_website/styles.dart';

part 'code_block.scopes.dart';

/// A highlighted, copyable code sample in a window-like frame.
@scopedCss
class CodeBlock extends StatelessComponent {
  const CodeBlock({
    required this.source,
    required this.language,
    this.title,
    this.copyText,
    this.deadLines = const {},
    this.lineNumbers = false,
    this.classes,
    super.key,
  });

  final String source;
  final Language language;

  /// Shown in the frame's title bar, e.g. a file name.
  final String? title;

  /// What the copy button copies. Defaults to [source]; pass `''` to hide the
  /// button.
  final String? copyText;

  /// 1-based lines to render struck through as dead code.
  final Set<int> deadLines;
  final bool lineNumbers;
  final ClassName? classes;

  static const _class = _$CodeBlockScope;

  // The frame, shared with [Terminal].
  static final _root = _class.root;
  static final _bar = _class('bar');
  static final _dots = _class('dots');
  static final _title = _class('title');
  static final _terminal = _class('terminal');
  static final _animated = _class('animated');
  static final _numbered = _class('numbered');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        minWidth: .zero,
        margin: .zero,
        border: hairline(borderColor),
        radius: const .circular(radius),
        overflow: .hidden,
        backgroundColor: surfaceColor,
        raw: {'box-shadow': shadow},
      ),
      css('& pre').styles(
        padding: .only(
          top: 1.rem,
          right: 1.1.rem,
          bottom: 1.1.rem,
          left: 1.1.rem,
        ),
        margin: .zero,
        overflow: .auto,
        fontSize: 0.8125.rem,
        lineHeight: const .expression('1.65'),
        raw: {
          'tab-size': '2',
          'scrollbar-width': 'thin',
          'scrollbar-color': 'var(--border-2) transparent',
        },
      ),
      css('& code').styles(display: .block, minWidth: .maxContent),
    ]),
    css(_bar.selector).styles(
      display: .flex,
      minHeight: 2.6.rem,
      padding: .only(
        top: 0.4.rem,
        right: 0.6.rem,
        bottom: 0.4.rem,
        left: 0.9.rem,
      ),
      border: .only(bottom: hairlineSide(borderColor)),
      alignItems: .center,
      gap: .all(0.75.rem),
      backgroundColor: surface2Color,
    ),
    css(_dots.selector, [
      css('&').styles(display: .inlineFlex, gap: .all(0.4.rem)),
      css('& span', [
        css('&').styles(
          width: 10.px,
          height: 10.px,
          radius: .circular(50.percent),
          backgroundColor: border2Color,
        ),
        css('&:first-child').styles(backgroundColor: accentColor),
      ]),
    ]),
    css(_title.selector).styles(
      minWidth: .zero,
      overflow: .hidden,
      color: mutedColor,
      textAlign: .center,
      fontFamily: fontMono,
      fontSize: 0.75.rem,
      textOverflow: .ellipsis,
      whiteSpace: .noWrap,
      raw: {'flex': '1'},
    ),
    css(Highlight.line.selector)
        .styles(display: .inlineBlock, minWidth: 100.percent),
    // Token colors, shared by the TextMate scopes and ciach's own output.
    css(Highlight.keyword.selector)
        .styles(color: const .variable('--tk-keyword')),
    css(Highlight.type.selector).styles(color: const .variable('--tk-type')),
    css(Highlight.string.selector)
        .styles(color: const .variable('--tk-string')),
    css(Highlight.number.selector)
        .styles(color: const .variable('--tk-number')),
    css(Highlight.comment.selector)
        .styles(color: const .variable('--tk-comment')),
    css(Highlight.annotation.selector)
        .styles(color: const .variable('--tk-annotation')),
    css(Highlight.function.selector)
        .styles(color: const .variable('--tk-function')),
    css(Highlight.key.selector).styles(color: const .variable('--tk-type')),
    css(Highlight.kind.selector).styles(color: const .variable('--tk-keyword')),
    css(Highlight.hint.selector).styles(color: const .variable('--tk-number')),
    css(Highlight.ask.selector)
        .styles(color: const .variable('--tk-annotation')),
    css(Highlight.doc.selector)
        .styles(color: const .variable('--tk-comment'), fontStyle: .italic),
    css(Highlight.flag.selector).styles(color: accentColor),
    css(Highlight.prompt.selector)
        .styles(userSelect: .none, color: accentColor, fontWeight: .w600),
    css(Highlight.command.selector).styles(color: textColor, fontWeight: .w600),
    css(Highlight.path.selector)
        .styles(color: const .variable('--tk-annotation'), fontWeight: .w600),
    css(Highlight.name.selector).styles(color: textColor),
    css(Highlight.summary.selector).styles(color: okColor, fontWeight: .w600),
    css('${Highlight.punct.selector}, ${Highlight.operator.selector}')
        .styles(color: const .variable('--tk-function')),
    // Transcripts wrap like a real terminal; code blocks keep scrolling because
    // indentation there carries meaning.
    css(_terminal.selector, [
      css('& pre').styles(
        color: text2Color,
        whiteSpace: .preWrap,
        raw: {'overflow-wrap': 'anywhere'},
      ),
      css('& code').styles(minWidth: .zero),
      // Wrapped continuations hang under the line's first character.
      css('& ${Highlight.line.selector}').styles(
        display: .inlineBlock,
        width: 100.percent,
        minWidth: .zero,
        padding: const .only(left: .expression('2.5ch')),
        textIndent: const .expression('-2.5ch'),
      ),
      // Sequential reveal for animated terminals.
      css('&${_animated.selector} ${Highlight.line.selector}', [
        css('&').styles(
          opacity: 0,
          animation: .new(
            name: 'reveal',
            duration: 350.ms,
            curve: .easeOut,
            fillMode: .forwards,
          ),
          raw: {'animation-delay': 'calc(var(--i, 0) * 110ms + 250ms)'},
        ),
        css.media(reducedMotion, [css('&').styles(opacity: 1)]),
      ]),
    ]),
    css.keyframes('reveal', {
      'from': .new(opacity: 0, transform: .translate(x: (-4).px)),
      'to': const .new(opacity: 1, transform: .none),
    }),
  ];

  @override
  Component build(BuildContext context) {
    final copy = copyText ?? source;
    return figure(
      classes: [
        _root.name,
        // Console output wraps like a terminal; real code scrolls.
        if (language == .console) _terminal.name,
        if (lineNumbers) _numbered.name,
        ?classes?.name,
      ].join(' '),
      [
        div(classes: _bar.name, [
          span(
            classes: _dots.name,
            attributes: const {'aria-hidden': 'true'},
            const [span([]), span([]), span([])],
          ),
          if (title case final title?)
            figcaption(classes: _title.name, [.text(title)])
          else
            span(classes: _title.name, const []),
          if (copy.isNotEmpty) CopyButton(text: copy),
        ]),
        pre(
          attributes: const {'tabindex': '0'},
          [
            code(
              classes: 'language-${language.name}',
              highlight(source, language, deadLines: deadLines),
            ),
          ],
        ),
      ],
    );
  }
}

/// A terminal transcript whose lines appear one after another.
class Terminal extends StatelessComponent {
  const Terminal({
    required this.transcript,
    this.title = 'zsh',
    this.animated = false,
    this.copyText = '',
    super.key,
  });

  final String transcript;
  final String title;

  /// Reveal lines sequentially with a CSS animation (respects
  /// `prefers-reduced-motion`).
  final bool animated;
  final String copyText;

  @override
  Component build(BuildContext context) {
    return figure(
      classes: [
        CodeBlock._root.name,
        CodeBlock._terminal.name,
        if (animated) CodeBlock._animated.name,
      ].join(' '),
      [
        div(classes: CodeBlock._bar.name, [
          span(
            classes: CodeBlock._dots.name,
            attributes: const {'aria-hidden': 'true'},
            const [span([]), span([]), span([])],
          ),
          figcaption(classes: CodeBlock._title.name, [.text(title)]),
          if (copyText.isNotEmpty) CopyButton(text: copyText),
        ]),
        pre(
          attributes: const {'tabindex': '0'},
          [
            code([
              for (final (index, line) in highlightLines(
                transcript,
                .console,
              ).indexed) ...[
                if (index > 0) const .text('\n'),
                span(
                  classes: Highlight.line.name,
                  styles: animated ? .new(raw: {'--i': '$index'}) : null,
                  line,
                ),
              ],
            ]),
          ],
        ),
      ],
    );
  }
}
