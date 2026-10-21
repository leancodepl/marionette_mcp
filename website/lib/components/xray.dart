import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/styles.dart';

part 'xray.scopes.dart';

/// One screen next to the element listing the agent got for it. Every
/// element's bounds are outlined faintly on the screenshot; pointing at or
/// focusing a line of the listing lights up its element. A switch shows the
/// compacted listing or the full one. CSS only.
///
/// Each line carries its own highlight box, positioned against the whole
/// component, whose top-left corner is the screenshot's. That keeps the
/// pairing of line and box in the markup instead of in per-element rules.
@scopedCss
class XRay extends StatelessComponent {
  const XRay({required this.xray, super.key});

  final XrayDemo xray;

  static const _class = _$XRayScope;

  static final _root = _class.root;
  static final _input = _class('input');
  static final _shot = _class('shot');
  static final _outline = _class('outline');
  static final _side = _class('side');
  static final _switch = _class('switch');
  static final _option = _class('option');
  static final _list = _class('list');
  static final _compactList = _class('compact-list');
  static final _noneList = _class('none-list');
  static final _row = _class('row');
  static final _mark = _class('mark');

  static final _narrow = MediaQuery.all(maxWidth: 719.px);

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        display: .grid,
        position: const .relative(),
        padding: .zero,
        margin: .zero,
        alignItems: .start,
        gap: .all(1.25.rem),
        raw: {
          '--shot-w': '250px',
          '--shot-h': 'calc(var(--shot-w) * var(--ratio))',
          'grid-template-columns': 'var(--shot-w) minmax(0, 1fr)',
        },
      ),
      css.media(_narrow, [
        css('&').styles(
          raw: {'grid-template-columns': 'minmax(0, 1fr)', '--shot-w': '210px'},
        ),
      ]),
    ]),
    css(_input.selector).styles(
      position: const .absolute(),
      width: 1.px,
      height: 1.px,
      opacity: 0,
      overflow: .hidden,
      raw: {'clip': 'rect(0 0 0 0)'},
    ),
    css(_shot.selector, [
      css('&').styles(
        position: const .relative(),
        width: const .expression('var(--shot-w)'),
        height: const .expression('var(--shot-h)'),
        border: hairline(border2Color),
        radius: .circular(6.px),
        overflow: .hidden,
        raw: {'grid-row': '1 / span 2', 'box-sizing': 'content-box'},
      ),
      css('& img')
          .styles(display: .block, width: 100.percent, height: 100.percent),
      css.media(_narrow, [
        css('&').styles(raw: {'grid-row': 'auto'}),
      ]),
    ]),
    css(_outline.selector).styles(
      position: const .absolute(),
      border: hairline(accentAlpha(0.28)),
      pointerEvents: .none,
    ),
    css(_side.selector)
        .styles(display: .grid, minWidth: .zero, gap: .all(0.75.rem)),
    css(_switch.selector).styles(
      display: .flex,
      padding: .all(0.25.rem),
      border: hairline(borderColor),
      radius: .circular(12.px),
      flexWrap: .wrap,
      gap: .all(0.25.rem),
      backgroundColor: surfaceColor,
      raw: {'width': 'fit-content'},
    ),
    css(_option.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 0.4.rem, horizontal: 0.8.rem),
        radius: .circular(9.px),
        cursor: .pointer,
        color: text2Color,
        fontSize: 0.85.rem,
      ),
      css('& span')
          .styles(color: mutedColor, fontFamily: fontMono, fontSize: 0.75.rem),
    ]),
    css(
      '${_input.selector}:nth-of-type(1):checked ~ ${_side.selector} '
      '${_option.selector}:nth-of-type(1), '
      '${_input.selector}:nth-of-type(2):checked ~ ${_side.selector} '
      '${_option.selector}:nth-of-type(2)',
    ).styles(color: accentInkColor, backgroundColor: accentColor),
    css(
      '${_input.selector}:nth-of-type(1):checked ~ ${_side.selector} '
      '${_option.selector}:nth-of-type(1) span, '
      '${_input.selector}:nth-of-type(2):checked ~ ${_side.selector} '
      '${_option.selector}:nth-of-type(2) span',
    ).styles(color: accentInkColor),
    css(
      '${_input.selector}:focus-visible ~ ${_side.selector} ${_switch.selector}',
    ).styles(
      outline: .new(
        color: accentColor,
        style: .solid,
        width: .new(2.px),
        offset: 2.px,
      ),
    ),
    css(_list.selector).styles(
      display: .none,
      maxHeight: const .expression('calc(var(--shot-h) - 3rem)'),
      padding: .all(0.4.rem),
      border: hairline(borderColor),
      radius: const .circular(radiusSm),
      overflow: const .only(y: .auto),
      backgroundColor: surfaceColor,
      raw: {
        'scrollbar-width': 'thin',
        'scrollbar-color': 'var(--border-2) transparent',
      },
    ),
    css(
      '${_input.selector}:nth-of-type(1):checked ~ ${_side.selector} '
      '${_compactList.selector}, '
      '${_input.selector}:nth-of-type(2):checked ~ ${_side.selector} '
      '${_noneList.selector}',
    ).styles(display: .block),
    css(_row.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 0.3.rem, horizontal: 0.5.rem),
        radius: .circular(5.px),
        cursor: .defaultCursor,
        color: text2Color,
        fontFamily: fontMono,
        fontSize: 0.7.rem,
        lineHeight: const .expression('1.5'),
        raw: {'overflow-wrap': 'anywhere'},
      ),
      css('&:hover, &:focus').styles(
        color: textColor,
        backgroundColor: accentSoftColor,
        raw: {'outline': 'none'},
      ),
      css('&:hover ${_mark.selector}, &:focus ${_mark.selector}')
          .styles(display: .block),
    ]),
    // Positioned against the component: x and y scale with the screenshot.
    css(_mark.selector).styles(
      display: .none,
      position: const .absolute(),
      border: .all(color: accentColor, width: 2.px),
      radius: .circular(3.px),
      pointerEvents: .none,
      backgroundColor: accentAlpha(0.14),
      raw: {
        'left': 'calc(1px + var(--x) * var(--shot-w))',
        'top': 'calc(1px + var(--y) * var(--shot-w))',
        'width': 'calc(var(--w) * var(--shot-w))',
        'height': 'calc(var(--h) * var(--shot-w))',
      },
    ),
  ];

  /// [bounds] as fractions of the screen width, the unit both axes scale
  /// by.
  Map<String, String> _fractions((double, double, double, double) bounds) {
    final (x, y, width, height) = bounds;
    String fraction(double value) =>
        (value / xray.logicalWidth).toStringAsFixed(4);
    return {
      '--x': fraction(x),
      '--y': fraction(y),
      '--w': fraction(width),
      '--h': fraction(height),
    };
  }

  /// [bounds] as percentages of the screenshot, for the faint outlines.
  Map<String, String> _percentages((double, double, double, double) bounds) {
    final (x, y, width, height) = bounds;
    String percent(double value, double of) =>
        '${(value / of * 100).toStringAsFixed(2)}%';
    return {
      'left': percent(x, xray.logicalWidth),
      'top': percent(y, xray.logicalHeight),
      'width': percent(width, xray.logicalWidth),
      'height': percent(height, xray.logicalHeight),
    };
  }

  Component _listing(
    ClassName mode,
    List<XrayElement> elements,
    String label,
  ) => div(
    classes: (_list + mode).name,
    attributes: {'role': 'list', 'aria-label': label},
    [
      for (final element in elements)
        div(
          classes: _row.name,
          attributes: const {'role': 'listitem', 'tabindex': '0'},
          [
            .text(element.raw),
            if (element.bounds case final bounds?)
              span(
                classes: _mark.name,
                styles: .new(raw: _fractions(bounds)),
                attributes: const {'aria-hidden': 'true'},
                const [],
              ),
          ],
        ),
    ],
  );

  @override
  Component build(BuildContext context) {
    final ratio = (xray.logicalHeight / xray.logicalWidth).toStringAsFixed(4);
    return figure(classes: _root.name, styles: .new(raw: {'--ratio': ratio}), [
      input(
        type: .radio,
        name: 'xray-mode',
        id: 'xray-compact',
        classes: _input.name,
        checked: true,
      ),
      input(
        type: .radio,
        name: 'xray-mode',
        id: 'xray-none',
        classes: _input.name,
      ),
      div(classes: _shot.name, [
        img(
          src: 'images/xray/${xray.screenshot}',
          alt: 'The Custom Widgets screen of the example app',
          attributes: const {'loading': 'lazy'},
        ),
        for (final element in xray.compact)
          if (element.bounds case final bounds?)
            span(
              classes: _outline.name,
              styles: .new(raw: _percentages(bounds)),
              const [],
            ),
      ]),
      div(classes: _side.name, [
        div(
          classes: _switch.name,
          attributes: const {'role': 'group', 'aria-label': 'Listing'},
          [
            label(
              classes: _option.name,
              attributes: const {'for': 'xray-compact'},
              [
                const .text('compact '),
                span([.text('${_thousands(xray.compactChars)} chars')]),
              ],
            ),
            label(
              classes: _option.name,
              attributes: const {'for': 'xray-none'},
              [
                const .text('none '),
                span([.text('${_thousands(xray.noneChars)} chars')]),
              ],
            ),
          ],
        ),
        _listing(_compactList, xray.compact, 'Compact listing'),
        _listing(_noneList, xray.none, 'Full listing'),
      ]),
    ]);
  }

  static String _thousands(int value) =>
      value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
}
