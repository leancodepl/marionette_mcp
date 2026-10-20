import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

part 'docs_toc.scopes.dart';

/// The docs table of contents.
///
/// Pre-rendered as plain links and hydrated on the client, where it follows
/// the reader's scroll position and marks the section currently in view.
/// Links carry the page path, because the document's `<base href>` would
/// otherwise resolve a bare `#fragment` against the site root.
@client
@scopedCss
class DocsToc extends StatefulComponent {
  const DocsToc({
    required this.path,
    required this.ids,
    required this.labels,
    super.key,
  });

  /// Absolute path of the page the sections live on, e.g. `/docs`.
  final String path;

  /// Section element ids, in page order.
  final List<String> ids;

  /// Link labels, parallel to [ids].
  final List<String> labels;

  static const _class = _$DocsTocScope;

  /// The link to the section in view; the docs page styles it.
  static final active = _class('active');

  @override
  State<DocsToc> createState() => _DocsTocState();
}

class _DocsTocState extends State<DocsToc> {
  String? _active;
  JSFunction? _listener;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      return;
    }
    _listener = ((web.Event _) => _schedule()).toJS;
    web.window.addEventListener('scroll', _listener);
    web.window.addEventListener('resize', _listener);
    web.window.addEventListener('hashchange', _listener);
    web.window.addEventListener('load', _listener);
    _update();
    // Once more after layout settles, e.g. after the browser scrolled to a
    // fragment on a fresh load.
    _schedule();
  }

  @override
  void dispose() {
    if (_listener case final listener?) {
      web.window.removeEventListener('scroll', listener);
      web.window.removeEventListener('resize', listener);
      web.window.removeEventListener('hashchange', listener);
      web.window.removeEventListener('load', listener);
    }
    super.dispose();
  }

  /// Coalesces bursts of scroll events into one measurement per frame.
  void _schedule() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    web.window.requestAnimationFrame(
      ((JSNumber _) {
        _scheduled = false;
        _update();
      }).toJS,
    );
  }

  /// The active section is the last one whose top has scrolled into the upper
  /// third of the viewport, the first section before any has, and the last
  /// one once the page is scrolled to the bottom.
  void _update() {
    final threshold = web.window.innerHeight * 0.3;
    String? active = component.ids.firstOrNull;
    for (final id in component.ids) {
      final element = web.document.getElementById(id);
      if (element == null) {
        continue;
      }
      if (element.getBoundingClientRect().top <= threshold) {
        active = id;
      }
    }
    final atBottom =
        web.window.scrollY + web.window.innerHeight >=
        web.document.documentElement!.scrollHeight - 2;
    if (atBottom && component.ids.isNotEmpty) {
      active = component.ids.last;
    }
    if (active != _active && mounted) {
      setState(() => _active = active);
    }
  }

  @override
  Component build(BuildContext context) {
    return ul([
      for (final (index, id) in component.ids.indexed)
        li([
          a(
            href: '${component.path}#$id',
            classes: id == _active ? DocsToc.active.name : null,
            attributes: id == _active ? const {'aria-current': 'true'} : null,
            [.text(component.labels[index])],
          ),
        ]),
    ]);
  }
}
