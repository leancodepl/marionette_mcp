import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/loop_player.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/styles.dart';

part 'the_loop.scopes.dart';

/// One recorded session, replayed: the agent's transcript, the phone it
/// drives, and the evidence the server writes, side by side.
///
/// Beat 0 is the prompt, beats 1…n the tool calls, beat n+1 the report.
/// [LoopPlayer] reveals them in order; without it the stage shows its end
/// state.
@scopedCss
class TheLoop extends StatelessComponent {
  const TheLoop({required this.loop, super.key});

  final LoopDemo loop;

  static const _stageId = 'loop-stage';

  static const _class = _$TheLoopScope;

  static final _stage = _class('stage');
  static final _pane = _class('pane');
  static final _bar = _class('bar');
  static final _dots = _class('dots');
  static final _title = _class('title');
  static final _scroll = _class('scroll');
  static final _you = _class('you');
  static final _who = _class('who');
  static final _call = _class('call');
  static final _result = _class('result');
  static final _done = _class('done');
  static final _thought = _class('thought');
  static final _phoneCol = _class('phone-col');
  static final _phone = _class('phone');
  static final _screen = _class('screen');
  static final _device = _class('device');
  static final _step = _class('step');
  static final _report = _class('report');
  static final _evidence = _class('evidence');
  static final _transcript = _class('transcript');

  static final _wide = MediaQuery.all(minWidth: 1100.px);
  static const _medium = MediaQuery.raw(
    '(min-width: 700px) and (max-width: 1099px)',
  );

  @css
  static List<StyleRule> get styles => [
    css(_stage.selector, [
      css('&').styles(
        display: .grid,
        alignItems: .start,
        gap: .all(1.25.rem),
        raw: {
          '--phone-w': '272px',
          '--pane-h': 'calc(var(--phone-w) * var(--ratio) + 22px)',
        },
      ),
      shrinkableChildren(),
      css.media(_wide, [
        css('&').styles(
          raw: {
            'grid-template-columns':
                'minmax(0, 1.1fr) var(--phone-w) minmax(0, 1fr)',
          },
        ),
      ]),
      css.media(_medium, [
        css('&').styles(
          raw: {'grid-template-columns': 'minmax(0, 1fr) var(--phone-w)'},
        ),
        css('& ${_evidence.selector}')
            .styles(raw: {'grid-column': '1 / -1', '--pane-h': '340px'}),
      ]),
      css.media(.all(maxWidth: 699.px), [
        css('&').styles(raw: {'--pane-h': '360px', '--phone-w': '240px'}),
        css('& ${_phoneCol.selector}').styles(order: -1),
      ]),
      // Armed by the player: a beat stays hidden until it plays.
      css(
        '&${LoopPlayer.armed.selector} [data-beat]:not(${LoopPlayer.shown.selector})',
      ).styles(display: .none),
      css('& ${LoopPlayer.shown.selector}').styles(
        animation: .new(
          name: 'beat-in',
          duration: 380.ms,
          curve: .easeOut,
          fillMode: .both,
        ),
      ),
    ]),
    css.keyframes('beat-in', {
      'from': .new(opacity: 0, transform: .translate(y: 4.px)),
      'to': const .new(opacity: 1, transform: .none),
    }),
    css(_pane.selector).styles(
      display: .flex,
      height: const .expression('var(--pane-h)'),
      minWidth: .zero,
      margin: .zero,
      border: hairline(borderColor),
      radius: const .circular(radius),
      overflow: .hidden,
      flexDirection: .column,
      backgroundColor: surfaceColor,
      raw: {'box-shadow': shadow},
    ),
    css(_bar.selector).styles(
      display: .flex,
      minHeight: 2.5.rem,
      padding: .symmetric(vertical: 0.4.rem, horizontal: 0.9.rem),
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
      color: mutedColor,
      fontFamily: fontMono,
      fontSize: 0.75.rem,
      raw: {'flex': '1'},
    ),
    css(_scroll.selector).styles(
      display: .grid,
      padding: .all(1.rem),
      overflow: const .only(y: .auto),
      alignContent: .start,
      gap: .all(0.55.rem),
      fontFamily: fontMono,
      fontSize: 0.78.rem,
      lineHeight: const .expression('1.55'),
      raw: {
        'flex': '1',
        'scroll-behavior': 'smooth',
        'scrollbar-width': 'thin',
        'scrollbar-color': 'var(--border-2) transparent',
        'overflow-wrap': 'anywhere',
      },
    ),
    css(_you.selector).styles(
      padding: .symmetric(vertical: 0.7.rem, horizontal: 0.85.rem),
      margin: .only(bottom: 0.4.rem),
      border: hairline(border2Color),
      radius: const .circular(radiusSm),
      color: textColor,
      fontFamily: fontSans,
      fontSize: 0.92.rem,
      backgroundColor: bgColor,
    ),
    css(_who.selector).styles(
      display: .block,
      margin: .only(bottom: 0.3.rem),
      color: mutedColor,
      fontFamily: fontMono,
      fontSize: 0.68.rem,
      fontWeight: .w600,
      textTransform: .upperCase,
      letterSpacing: 0.08.em,
    ),
    css(_call.selector, [
      css('&').styles(color: textColor),
      css('&::before').styles(content: '● ', color: accentColor),
    ]),
    css(_result.selector).styles(
      padding: .only(left: 1.1.rem),
      margin: .only(top: (-0.4).rem),
      color: mutedColor,
    ),
    css(_done.selector).styles(color: okColor),
    css(_thought.selector).styles(
      color: text2Color,
      fontFamily: fontSans,
      fontSize: 0.86.rem,
      fontStyle: .italic,
    ),
    css(_phoneCol.selector)
        .styles(display: .grid, justifyItems: .center, gap: .all(0.6.rem)),
    css(_phone.selector).styles(
      width: const .expression('var(--phone-w)'),
      padding: .all(10.px),
      border: hairline(border2Color),
      radius: .circular(34.px),
      backgroundColor: bg2Color,
      raw: {'box-shadow': shadow},
    ),
    css(_screen.selector, [
      css('&').styles(
        position: const .relative(),
        width: 100.percent,
        radius: .circular(24.px),
        overflow: .hidden,
        backgroundColor: surface2Color,
        raw: {'aspect-ratio': '1 / var(--ratio)'},
      ),
      css('& img').styles(
        display: .block,
        position: const .absolute(),
        width: 100.percent,
        height: 100.percent,
        raw: {'inset': '0', 'object-fit': 'cover'},
      ),
    ]),
    css(_device.selector)
        .styles(color: mutedColor, fontFamily: fontMono, fontSize: 0.72.rem),
    css(_step.selector).styles(color: text2Color),
    css(_report.selector, [
      css('&').styles(
        padding: .only(top: 0.8.rem),
        margin: .only(top: 0.4.rem),
        border: .only(top: hairlineSide(border2Color)),
      ),
      css('& pre').styles(
        margin: .zero,
        color: textColor,
        fontFamily: fontMono,
        whiteSpace: .preWrap,
      ),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final beats = loop.beats;
    final reportBeat = beats.length + 1;
    return Section(
      id: 'loop',
      eyebrow: 'One real run',
      heading: 'Prompt in. Evidence out.',
      lead:
          'Recorded on the example app in this repository, driven through '
          'Marionette itself. Every tool call, screen and `steps.md` line '
          'below comes from that session.',
      children: [
        div(
          id: _stageId,
          classes: _stage.name,
          styles: .new(raw: {'--ratio': _ratio}),
          [
            figure(classes: (_pane + _transcript).name, [
              _frameBar('agent'),
              div(
                classes: _scroll.name,
                attributes: const {'data-follow': ''},
                [
                  div(classes: _you.name, attributes: _at(0), [
                    span(classes: _who.name, const [.text('You')]),
                    .text(loop.prompt),
                  ]),
                  for (final (i, beat) in beats.indexed) ...[
                    div(classes: _call.name, attributes: _at(i + 1), [
                      .text(beat.call),
                    ]),
                    div(
                      classes: _result.name,
                      attributes: _at(i + 1, answer: true),
                      [.text('⎿  ${beat.result}')],
                    ),
                    if (beat.observation case final observation?)
                      div(
                        classes: _thought.name,
                        attributes: _at(i + 1, answer: true),
                        [.text(observation)],
                      ),
                  ],
                  div(
                    classes: (_call + _done).name,
                    attributes: _at(reportBeat),
                    const [.text('Wrote report.md')],
                  ),
                ],
              ),
            ]),
            div(classes: _phoneCol.name, [
              div(classes: _phone.name, [
                div(classes: _screen.name, [
                  img(
                    src: 'images/loop/${loop.firstFrame}',
                    alt: 'The example app before the run',
                    attributes: _at(0),
                  ),
                  for (final (i, beat) in beats.indexed)
                    if (beat.frame case final frame?)
                      img(
                        src: 'images/loop/$frame',
                        alt: 'The example app after ${beat.call}',
                        attributes: {
                          ..._at(i + 1, answer: true),
                          'loading': 'lazy',
                        },
                      ),
                ]),
              ]),
              p(classes: _device.name, [.text(loop.deviceName)]),
            ]),
            figure(classes: (_pane + _evidence).name, [
              _frameBar('.marionette/sessions/…/steps.md'),
              div(
                classes: _scroll.name,
                attributes: const {'data-follow': ''},
                [
                  for (final (i, beat) in beats.indexed)
                    div(
                      classes: _step.name,
                      attributes: _at(i + 1, answer: true),
                      [.text(beat.step)],
                    ),
                  div(classes: _report.name, attributes: _at(reportBeat), [
                    span(classes: _who.name, const [.text('report.md')]),
                    pre([.text(loop.report)]),
                  ]),
                ],
              ),
            ]),
          ],
        ),
        LoopPlayer(targetId: _stageId, beats: beats.length + 2),
      ],
    );
  }

  /// Height over width of the recorded screen.
  String get _ratio {
    final frameHeight = loop.logicalHeight / loop.logicalWidth;
    return frameHeight.toStringAsFixed(4);
  }

  static Map<String, String> _at(int beat, {bool answer = false}) => {
    'data-beat': '$beat',
    if (answer) 'data-at': 'answer',
  };

  static Component _frameBar(String title) => div(classes: _bar.name, [
    span(
      classes: _dots.name,
      attributes: const {'aria-hidden': 'true'},
      const [span([]), span([]), span([])],
    ),
    figcaption(classes: _title.name, [.text(title)]),
  ]);
}
