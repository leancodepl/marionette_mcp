/// Build-time syntax highlighting.
///
/// Tokenizing is done by `syntax_highlight_lite`, the pure-Dart TextMate
/// engine behind `jaspr_content`, while the site is pre-rendered. Its scopes
/// are mapped to CSS classes here, so the browser receives finished `<span>`
/// markup and never downloads a highlighting library.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/grammars/console_grammar.dart';
import 'package:marionette_website/grammars/json_grammar.dart';
import 'package:marionette_website/grammars/shell_grammar.dart';
import 'package:marionette_website/grammars/yaml_grammar.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart' as sh;

part 'highlight.scopes.dart';

enum Language {
  dart,
  yaml,
  shell,
  json,

  /// Marionette's own output, such as `steps.md` lines and reports, with
  /// shell prompts.
  console,
}

/// Registers the grammars. Call once before rendering; the Dart grammar ships
/// with the engine, the rest live in `grammars/`.
Future<void> initHighlighting() async {
  await sh.Highlighter.initialize(['dart']);
  sh.Highlighter.addLanguage(Language.yaml.name, kYamlGrammar);
  sh.Highlighter.addLanguage(Language.json.name, kJsonGrammar);
  sh.Highlighter.addLanguage(Language.shell.name, kShellGrammar);
  sh.Highlighter.addLanguage(Language.console.name, kConsoleGrammar);
}

/// The classes highlighted code is rendered with: one per line, and one per
/// token kind. `CodeBlock` gives them their look.
@scopedCss
abstract final class Highlight {
  static const _class = _$HighlightScope;

  /// Every line of highlighted code.
  static final line = _class('line');

  /// A line struck through as dead code, together with [line].
  static final dead = _class('dead');

  // Token kinds, shared by the TextMate scopes and Marionette's own output.
  static final doc = _class('doc');
  static final comment = _class('comment');
  static final string = _class('string');
  static final number = _class('number');
  static final keyword = _class('keyword');
  static final punct = _class('punct');
  static final operator = _class('operator');
  static final prompt = _class('prompt');
  static final kind = _class('kind');
  static final annotation = _class('annotation');
  static final flag = _class('flag');
  static final type = _class('type');
  static final key = _class('key');
  static final path = _class('path');
  static final command = _class('command');
  static final name = _class('name');
  static final function = _class('function');
  static final summary = _class('summary');
  static final ask = _class('ask');
  static final hint = _class('hint');
}

/// Colors come from CSS classes, not from the engine's theme, so the theme is
/// empty. Its text style is required but never rendered.
final _theme = sh.HighlighterTheme.fromConfiguration(
  '{"settings": []}',
  .new(foreground: const .new(0)),
);

final _highlighters = <Language, sh.Highlighter>{};

/// TextMate scope prefixes to token classes. For each token the innermost
/// scope is tried first, longest prefix first; a scope with no entry falls
/// through to its parent, so punctuation inside a string stays a string.
final _scopeClasses = <String, ClassName>{
  'comment.block.documentation': Highlight.doc,
  'comment': Highlight.comment,
  'string': Highlight.string,
  'constant.character.escape': Highlight.string,
  'constant.numeric': Highlight.number,
  'constant.language': Highlight.keyword,
  'keyword.operator.pipe': Highlight.punct,
  'keyword.operator': Highlight.operator,
  'keyword.other.prompt': Highlight.prompt,
  'keyword.kind': Highlight.kind,
  'keyword': Highlight.keyword,
  'storage.type.annotation': Highlight.annotation,
  'storage': Highlight.keyword,
  'variable.language': Highlight.keyword,
  'variable.other.flag': Highlight.flag,
  'support.class': Highlight.type,
  'support.type.property-name': Highlight.key,
  'entity.name.tag.path': Highlight.path,
  'entity.name.tag': Highlight.key,
  'entity.name.command': Highlight.command,
  'entity.name.declaration': Highlight.name,
  'entity.name.function': Highlight.function,
  'entity.name.type': Highlight.type,
  'meta.embedded.expression': Highlight.annotation,
  'markup.inserted': Highlight.summary,
  'markup.changed': Highlight.ask,
  'invalid.hint': Highlight.hint,
};

/// Highlights [source] and wraps each line in a [Highlight.line] span, which
/// lets CSS mark the 1-based [deadLines] as dead code.
List<Component> highlight(
  String source,
  Language language, {
  Set<int> deadLines = const {},
}) {
  var dead = 0;
  return [
    for (final (index, line) in highlightLines(source, language).indexed) ...[
      if (index > 0) const .text('\n'),
      if (deadLines.contains(index + 1))
        // `--d` is the line's position among the dead ones, so CSS can
        // stagger the strike-through animation.
        span(
          classes: (Highlight.line + Highlight.dead).name,
          styles: .new(raw: {'--d': '${dead++}'}),
          line,
        )
      else
        span(classes: Highlight.line.name, line),
    ],
  ];
}

/// Highlights [source] and returns the tokens of each line separately, for
/// callers that lay lines out themselves.
List<List<Component>> highlightLines(String source, Language language) {
  final highlighter = _highlighters.putIfAbsent(
    language,
    () => .new(language: language.name, theme: _theme),
  );
  final lines = <List<Component>>[<Component>[]];
  for (final (text, className) in _flatten(highlighter.highlight(source))) {
    final parts = text.split('\n');
    for (final (index, part) in parts.indexed) {
      if (index > 0) {
        lines.add(<Component>[]);
      }
      if (part.isEmpty) {
        continue;
      }
      lines.last.add(
        className == null
            ? .text(part)
            : span(classes: className.name, [.text(part)]),
      );
    }
  }
  return lines;
}

/// Walks the span tree into `(text, class)` runs, in document order.
Iterable<(String, ClassName?)> _flatten(sh.TextSpan node) sync* {
  if (node.text case final text?) {
    yield (text, _classFor(node.scopes));
  }
  for (final child in node.children) {
    yield* _flatten(child);
  }
}

ClassName? _classFor(List<String> scopes) {
  for (final scope in scopes.reversed) {
    final parts = scope.split('.');
    for (var length = parts.length; length > 0; length--) {
      final className = _scopeClasses[parts.take(length).join('.')];
      if (className != null) {
        return className;
      }
    }
  }
  return null;
}
