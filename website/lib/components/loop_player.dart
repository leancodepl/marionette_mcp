import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/components/icons.dart';
import 'package:marionette_website/styles.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

part 'loop_player.scopes.dart';

/// Plays the recorded session in `#[targetId]` beat by beat.
///
/// The target is pre-rendered in its end state: every line, the last screen
/// and the report, so the page is complete without JavaScript. Hydration
/// arms it (everything tagged `data-beat` is hidden) and the run plays once
/// the stage scrolls into view: each beat shows its tool call first, then,
/// a moment later, what it answered, the screen it left and its `steps.md`
/// line. Readers who asked for less motion get the end state and the Step
/// button.
@client
@scopedCss
class LoopPlayer extends StatefulComponent {
  const LoopPlayer({required this.targetId, required this.beats, super.key});

  final String targetId;

  /// The number of beats, the prompt (beat 0) and the report included.
  final int beats;

  static const _class = _$LoopPlayerScope;

  /// Set on the target once the script runs: hides every beat not yet shown.
  static final armed = _class('armed');

  /// Set on an element of the target when its beat plays.
  static final shown = _class('shown');

  static final _root = _class.root;
  static final _button = _class('button');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(
      display: .flex,
      margin: .only(top: 1.25.rem),
      flexWrap: .wrap,
      justifyContent: .center,
      gap: .all(0.5.rem),
    ),
    css(_button.selector, [
      css('&').styles(
        display: .inlineFlex,
        padding: .symmetric(vertical: 0.5.rem, horizontal: 0.9.rem),
        border: hairline(border2Color),
        radius: .circular(999.px),
        cursor: .pointer,
        alignItems: .center,
        gap: .all(0.45.rem),
        color: text2Color,
        backgroundColor: surfaceColor,
        raw: {'font': '600 0.85rem/1 var(--font-sans)'},
      ),
      css('&:hover')
          .styles(color: textColor, raw: {'border-color': 'var(--accent)'}),
      css('&:disabled').styles(opacity: 0.45, cursor: .defaultCursor),
    ]),
  ];

  @override
  State<LoopPlayer> createState() => _LoopPlayerState();
}

class _LoopPlayerState extends State<LoopPlayer> {
  /// How long a beat's tool call shows before its answer does, and how long
  /// the answer holds before the next call.
  static const _answerDelay = Duration(milliseconds: 800);
  static const _hold = Duration(milliseconds: 1900);

  web.Element? _target;
  web.IntersectionObserver? _observer;
  Timer? _timer;

  /// The last beat fully shown; -1 before the prompt.
  int _beat = -1;
  bool _playing = false;

  bool get _done => _beat >= component.beats - 1;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      return;
    }
    final target = web.document.getElementById(component.targetId);
    if (target == null) {
      return;
    }
    _target = target;
    if (web.window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      // The end state stays; Step and Replay still work, without autoplay.
      _beat = component.beats - 1;
      return;
    }
    _reset();
    _observer = .new(
      ((
            JSArray<web.IntersectionObserverEntry> entries,
            web.IntersectionObserver _,
          ) {
            for (final entry in entries.toDart) {
              if (entry.isIntersecting) {
                _observer?.disconnect();
                _play();
                return;
              }
            }
          })
          .toJS,
      .new(threshold: 0.35.toJS),
    )..observe(target);
  }

  @override
  void dispose() {
    _observer?.disconnect();
    _timer?.cancel();
    super.dispose();
  }

  void _reset() {
    _timer?.cancel();
    final target = _target!;
    target.classList.add(LoopPlayer.armed.name);
    final shown = target.querySelectorAll('.${LoopPlayer.shown.name}');
    for (var i = 0; i < shown.length; i++) {
      (shown.item(i)! as web.Element).classList.remove(LoopPlayer.shown.name);
    }
    _beat = -1;
  }

  /// Shows the parts of [beat] that appear at [phase]: `call` first, then
  /// `answer`; untagged parts show with the call.
  void _show(int beat, String phase) {
    final target = _target!;
    final parts = target.querySelectorAll('[data-beat="$beat"]');
    for (var i = 0; i < parts.length; i++) {
      final part = parts.item(i)! as web.Element;
      final at = part.getAttribute('data-at') ?? 'call';
      if (at == phase) {
        part.classList.add(LoopPlayer.shown.name);
      }
    }
    // Keep the newest line of every scrolling pane in view.
    final panes = target.querySelectorAll('[data-follow]');
    for (var i = 0; i < panes.length; i++) {
      final pane = panes.item(i)! as web.Element;
      pane.scrollTop = pane.scrollHeight.toDouble();
    }
  }

  void _advance() {
    _beat++;
    _show(_beat, 'call');
    _timer = .new(_answerDelay, () {
      _show(_beat, 'answer');
      if (_playing && !_done) {
        _timer = .new(_hold, _advance);
      } else if (_done) {
        setState(() => _playing = false);
      }
    });
  }

  void _play() {
    setState(() => _playing = true);
    _advance();
  }

  void _replay() {
    if (_target == null) {
      return;
    }
    _reset();
    _play();
  }

  void _step() {
    if (_target == null || _done) {
      return;
    }
    _timer?.cancel();
    if (_beat >= 0) {
      // Finish the current beat before moving on.
      _show(_beat, 'answer');
    }
    setState(() => _playing = false);
    _target!.classList.add(LoopPlayer.armed.name);
    _beat++;
    _show(_beat, 'call');
    _show(_beat, 'answer');
    if (_done) {
      setState(() {});
    }
  }

  @override
  Component build(BuildContext context) {
    return div(
      classes: LoopPlayer._root.name,
      attributes: const {'role': 'group', 'aria-label': 'Replay controls'},
      [
        button(
          classes: LoopPlayer._button.name,
          attributes: const {'type': 'button'},
          onClick: _replay,
          [Icon.refresh.build(size: 16), const .text('Replay')],
        ),
        button(
          classes: LoopPlayer._button.name,
          attributes: {'type': 'button', if (_done) 'disabled': ''},
          onClick: _step,
          [Icon.step.build(size: 16), const .text('Step')],
        ),
      ],
    );
  }
}
