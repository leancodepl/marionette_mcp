import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/styles.dart';

part 'faq.scopes.dart';

class FaqEntry {
  const FaqEntry(this.question, this.answer);

  final String question;
  final String answer;
}

/// Shared with the FAQPage JSON-LD, so the structured data and the visible
/// answers can never drift apart. Backticks mark inline code; the structured
/// data drops them.
const faqEntries = [
  FaqEntry(
    'Does it work in release builds?',
    'No, by design. Marionette reaches the app through the Dart VM service, '
        'which exists only in debug and profile builds. Gate the binding on '
        '`kDebugMode`, or on `!kReleaseMode` to include profile builds, and '
        'nothing of it reaches the release binary.',
  ),
  FaqEntry(
    'Which agents does it work with?',
    'Any agent with MCP support, such as Claude Code, Codex, Cursor, Gemini '
        'CLI, Copilot or Antigravity, through the MCP server. Any agent that '
        'runs shell commands, through the `marionette` CLI. Most agents can '
        'use either.',
  ),
  FaqEntry(
    'Do I have to change my widgets?',
    "Not for Flutter's own widgets. A custom design system needs "
        '`isInteractiveElement`, and usually `extractText`, in the '
        'configuration. A `ValueKey` or a `Semantics(identifier:)` gives the '
        'agent a stable target.',
  ),
  FaqEntry(
    'Can it handle permission dialogs, pickers and WebViews?',
    'Yes, through the native lane: the `native_*` tools drive UI that the '
        'platform draws, such as permission dialogs, pickers, WebView '
        'content, native views and notifications, on an Android device or '
        'emulator and the iOS Simulator.',
  ),
  FaqEntry(
    'Does it replace integration tests or Patrol?',
    'No. Its gestures simulate a user on a best-effort basis, which is right '
        'for an agent checking its own work. For a suite that must pass or '
        'fail the same way on every CI run, use Patrol.',
  ),
  FaqEntry(
    'How does the agent find my app?',
    'You give it the `ws://` VM service URI that `flutter run` prints, for '
        'example `ws://127.0.0.1:9101/ws`. Pasting it into the prompt is the '
        'most reliable way.',
  ),
  FaqEntry(
    '`connect` fails with a version mismatch.',
    '`marionette_mcp` checks that the app runs the same version of '
        '`marionette_flutter`. Upgrade both packages together.',
  ),
  FaqEntry(
    'Is it free?',
    'Yes. Marionette is open source under the Apache 2.0 license and '
        'maintained by LeanCode.',
  ),
];

/// FAQ as `<details>` disclosures: no script, every answer in the HTML.
@scopedCss
class Faq extends StatelessComponent {
  const Faq({super.key});

  static const _class = _$FaqScope;

  static final _root = _class.root;
  static final _item = _class('item');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(
      maxWidth: 52.rem,
      border: .only(top: hairlineSide(borderColor)),
    ),
    css(_item.selector, [
      css('&').styles(
        border: .only(bottom: hairlineSide(borderColor)),
        // Lets block-size animate to `auto`, so the answer slides open and
        // shut.
        raw: {'interpolate-size': 'allow-keywords'},
      ),
      // The answer panel: collapsed to zero height and faded out when closed,
      // transitioned to its natural height when open. Browsers without
      // `::details-content` transitions fall back to an instant toggle.
      css('&::details-content').styles(
        opacity: 0,
        overflow: .clip,
        raw: {
          'block-size': '0',
          'transition':
              'block-size 0.3s ease, opacity 0.25s ease, '
              'content-visibility 0.3s allow-discrete',
        },
      ),
      css('&[open]::details-content')
          .styles(opacity: 1, raw: {'block-size': 'auto'}),
      css('& summary', [
        css('&').styles(
          display: .flex,
          padding: .symmetric(vertical: 1.25.rem, horizontal: .zero),
          cursor: .pointer,
          justifyContent: .spaceBetween,
          alignItems: .center,
          gap: .all(1.rem),
          listStyle: .none,
        ),
        css('&::-webkit-details-marker').styles(display: .none),
        css('& h3').styles(fontSize: 1.1.rem, fontWeight: .w500),
        css('&::after').styles(
          content: '+',
          display: .grid,
          width: 2.rem,
          height: 2.rem,
          border: hairline(border2Color),
          radius: .circular(50.percent),
          transition: .new('transform', duration: 200.ms, curve: .ease),
          flex: .none,
          color: accentColor,
          fontFamily: fontMono,
          raw: {'place-items': 'center'},
        ),
        css('&:hover h3').styles(color: accentColor),
      ]),
      css('&[open] summary::after').styles(transform: .rotate(45.deg)),
      css('& p').styles(
        maxWidth: 46.rem,
        padding: .only(bottom: 1.5.rem),
        color: text2Color,
      ),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: _root.name, [
      for (final (index, entry) in faqEntries.indexed)
        details(
          classes: _item.name,
          attributes: {'name': 'faq', if (index == 0) 'open': ''},
          [
            summary([h3(rich(entry.question))]),
            p(rich(entry.answer)),
          ],
        ),
    ]);
  }
}

String _plain(String text) => text.replaceAll('`', '');

Map<String, Object?> faqStructuredData() => {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  'mainEntity': [
    for (final entry in faqEntries)
      {
        '@type': 'Question',
        'name': _plain(entry.question),
        'acceptedAnswer': {'@type': 'Answer', 'text': _plain(entry.answer)},
      },
  ],
};
