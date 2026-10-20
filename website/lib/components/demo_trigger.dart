import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:marionette_website/styles.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

part 'demo_trigger.scopes.dart';

/// Starts the dead-code animation on `#[targetId]` the first time it scrolls
/// into view.
///
/// Without JavaScript the target shows its end state (struck, faded lines).
/// With it, hydration first arms the target so nothing is struck yet, and
/// the animation plays once the block is on screen.
@client
@scopedCss
class DemoTrigger extends StatefulComponent {
  const DemoTrigger({required this.targetId, super.key});

  final String targetId;

  static const _class = _$DemoTriggerScope;

  /// Set on the target once the script runs, so its styles can hide the end
  /// state until the animation plays.
  static final armed = _class('armed');

  /// Set on the target when it scrolls into view, to play the animation.
  static final play = _class('play');

  @override
  State<DemoTrigger> createState() => _DemoTriggerState();
}

class _DemoTriggerState extends State<DemoTrigger> {
  web.IntersectionObserver? _observer;

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
    target.classList.add(DemoTrigger.armed.name);
    _observer = .new(
      ((
            JSArray<web.IntersectionObserverEntry> entries,
            web.IntersectionObserver _,
          ) {
            for (final entry in entries.toDart) {
              if (entry.isIntersecting) {
                target.classList.add(DemoTrigger.play.name);
                _observer?.disconnect();
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
    super.dispose();
  }

  @override
  Component build(BuildContext context) =>
      span(classes: Utility.srOnly.name, const []);
}
