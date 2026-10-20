/// Design tokens and the site-wide rules: the reset, typography and shared
/// utilities. Everything else lives next to the component it styles, in `@css`
/// getters, under class names scoped to that component; Jaspr collects all of
/// them into one stylesheet, global rules first, and inlines it into every
/// page.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/palette.dart';

// ---------- Tokens ----------
//
// The palette (`palette.dart`) and metrics are CSS custom properties on
// `:root`, so the values below are the variables, and the definitions sit in
// [styles].

const bgColor = Color.variable('--bg');
const bg2Color = Color.variable('--bg-2');
const surfaceColor = Color.variable('--surface');
const surface2Color = Color.variable('--surface-2');
const borderColor = Color.variable('--border');
const border2Color = Color.variable('--border-2');
const textColor = Color.variable('--text');
const text2Color = Color.variable('--text-2');
const mutedColor = Color.variable('--muted');
const accentColor = Color.variable('--accent');
const accentInkColor = Color.variable('--accent-ink');
const accentSoftColor = Color.variable('--accent-soft');
const dangerColor = Color.variable('--danger');
const okColor = Color.variable('--ok');

const fontSans = FontFamily.variable('--font-sans');
const fontMono = FontFamily.variable('--font-mono');

const radius = Unit.variable('--radius');
const radiusSm = Unit.variable('--radius-sm');
const headerHeight = Unit.variable('--header-h');

/// `var(--shadow)`, for the `box-shadow` slot of a `raw` map: `BoxShadow` has no
/// variable form.
const shadow = 'var(--shadow)';

/// The accent at a given alpha, for borders and glows.
Color accentAlpha(double alpha) => Palette.ctaYellow.alpha(alpha);

/// Marks a link inside running text by more than its color.
const underlined = TextDecoration(line: .underline);

/// Matches readers who asked the system for less motion.
const reducedMotion = MediaQuery.raw('(prefers-reduced-motion: reduce)');

/// Lets the children of a grid or flex container shrink below their content,
/// for a nested `css()` rule. They may hold wide code samples, which should
/// scroll instead of stretching the page.
StyleRule shrinkableChildren() => css('& > *').styles(minWidth: .zero);

/// A 1px solid border in [color].
Border hairline(Color color) => .all(color: color, width: 1.px);

/// One side of a [hairline], for `Border.only`.
BorderSide hairlineSide(Color color) => .new(color: color, width: 1.px);

/// Everything the page needs before any component draws: tokens, the reset,
/// typography and utilities.
@css
List<StyleRule> get styles => [
  ..._tokens,
  ..._reset,
  ..._utilities,
  ..._motion,
];

List<StyleRule> get _tokens => [
  css(':root').styles(
    raw: {
      '--bg': Palette.black.hex,
      '--bg-2': Palette.nearBlack.hex,
      '--surface': Palette.surface.hex,
      '--surface-2': Palette.surface2.hex,
      '--border': Palette.line.value,
      '--border-2': Palette.lineStrong.value,
      '--text': Palette.white.hex,
      '--text-2': Palette.bodyGray.hex,
      '--muted': Palette.mutedGray.hex,
      '--accent': Palette.ctaYellow.hex,
      '--accent-ink': Palette.black.hex,
      '--accent-soft': accentAlpha(0.06).value,
      '--danger': Palette.error.hex,
      '--ok': Palette.success.hex,
      '--tk-keyword': '#c792ea',
      '--tk-type': '#82aaff',
      '--tk-string': '#c3e88d',
      '--tk-number': '#f78c6c',
      '--tk-comment': '#767eaa',
      '--tk-annotation': '#ffcb6b',
      '--tk-function': '#89ddff',
      '--font-sans':
          "'Space Grotesk', ui-sans-serif, system-ui, -apple-system, "
          "'Segoe UI', Roboto, sans-serif",
      '--font-mono':
          "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, "
          'monospace',
      '--radius': '14px',
      '--radius-sm': '8px',
      '--container': '1160px',
      '--header-h': '68px',
      '--shadow': '0 24px 60px -32px ${Palette.black.alpha(0.9).value}',
      'color-scheme': 'dark',
    },
  ),
];

List<StyleRule> get _reset => [
  css('*, *::before, *::after').styles(boxSizing: .borderBox),
  css('html', [
    css('&').styles(
      raw: {
        'scroll-behavior': 'smooth',
        'scroll-padding-top': 'calc(var(--header-h) + 16px)',
        '-webkit-text-size-adjust': '100%',
      },
    ),
    css.media(reducedMotion, [
      css('&').styles(raw: {'scroll-behavior': 'auto'}),
    ]),
  ]),
  css('body').styles(
    margin: .zero,
    color: textColor,
    fontFamily: fontSans,
    fontSize: 1.0625.rem,
    lineHeight: const .expression('1.6'),
    backgroundColor: bgColor,
    raw: {
      '-webkit-font-smoothing': 'antialiased',
      'text-rendering': 'optimizeLegibility',
    },
  ),
  css('h1, h2, h3').styles(
    margin: .zero,
    fontWeight: .w600,
    letterSpacing: (-0.02).em,
    lineHeight: const .expression('1.15'),
    raw: {'text-wrap': 'balance'},
  ),
  css('p').styles(margin: .zero),
  css('a', [
    css('&').styles(color: .inherit, textDecoration: .none),
    css('&:hover').styles(color: accentColor),
  ]),
  css(':focus-visible').styles(
    radius: .circular(4.px),
    outline: .new(
      color: accentColor,
      style: .solid,
      width: .new(2.px),
      offset: 3.px,
    ),
  ),
  css('code, pre, kbd')
      .styles(fontFamily: fontMono, raw: {'font-feature-settings': "'liga' 0"}),
  // Inline code chips. A flag or identifier never breaks at one of its
  // hyphens. Code blocks inside a list item keep their own look.
  css(':where(p, li, td, th) code:not(pre code)').styles(
    padding: .symmetric(vertical: 0.1.em, horizontal: 0.4.em),
    border: hairline(borderColor),
    radius: .circular(6.px),
    fontSize: 0.85.em,
    whiteSpace: .noWrap,
    backgroundColor: surfaceColor,
  ),
  css('ul, ol').styles(padding: .zero, margin: .zero, listStyle: .none),
  css('svg').styles(
    display: .inlineBlock,
    flex: .none,
    raw: {'vertical-align': 'middle'},
  ),
];

/// Site-wide utility classes. Every component may use them, so they render as
/// written instead of being scoped to one.
abstract final class Utility {
  /// Centers the content in a column of at most `--container`.
  static const container = ClassName.shared('container');

  /// Hides an element from sight but not from screen readers.
  static const srOnly = ClassName.shared('sr-only');

  /// Draws text in the accent color.
  static const accent = ClassName.shared('accent');

  /// Draws text in the muted color.
  static const muted = ClassName.shared('muted');

  /// Hides inline text on narrow screens.
  static const hideSm = ClassName.shared('hide-sm');
}

List<StyleRule> get _utilities => [
  css(Utility.container.selector).styles(
    width: const .expression('min(100% - 2.5rem, var(--container))'),
    raw: {'margin-inline': 'auto'},
  ),
  css(Utility.srOnly.selector).styles(
    width: 1.px,
    height: 1.px,
    padding: .zero,
    margin: .all((-1).px),
    overflow: .hidden,
    whiteSpace: .noWrap,
    raw: {
      'position': 'absolute !important',
      'clip': 'rect(0 0 0 0)',
      'border': '0',
    },
  ),
  css(Utility.accent.selector).styles(color: accentColor),
  css(Utility.muted.selector).styles(color: mutedColor),
  css(Utility.hideSm.selector, [
    css('&').styles(display: .inline),
    css.media(.all(maxWidth: 540.px), [css('&').styles(display: .none)]),
  ]),
];

// Motion is a garnish here; readers who asked for less of it get none.
List<StyleRule> get _motion => [
  css.media(reducedMotion, [
    css('*, *::before, *::after').styles(
      raw: {
        'animation-duration': '0.01ms !important',
        'animation-iteration-count': '1 !important',
        'transition-duration': '0.01ms !important',
      },
    ),
  ]),
];
