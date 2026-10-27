import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/docs_layout.dart';
import 'package:marionette_website/components/docs_widgets.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/components/xray.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/site.dart';

const _scoped = '''
{ "key": "cell.joinButton", "ancestor_keys": ["session_2", "grid.cell_3"] }''';

const _skipUnderTest = '''
import 'dart:io' show Platform;

final isFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
if (kDebugMode && !isFlutterTest) {
  MarionetteBinding.ensureInitialized();
} else {
  WidgetsFlutterBinding.ensureInitialized();
}''';

const _sentry = '''
void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(); // before Sentry, not inside appRunner
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  SentryFlutter.init(
    (options) => options.dsn = _sentryDsn,
    appRunner: () => runApp(const MyApp()),
  );
}''';

const _toc = [
  ('how', 'How it works'),
  ('seeing', 'How the agent sees'),
  ('targets', 'Choosing a target'),
  ('compaction', 'Compact by default'),
  ('builds', 'Debug and profile only'),
  ('binding', 'One binding per process'),
  ('mcp-or-cli', 'MCP server or CLI'),
  ('fit', 'When not to use it'),
];

/// Docs, page 2: the model behind the tools.
class ConceptsPage extends StatelessComponent {
  const ConceptsPage({required this.version, required this.xray, super.key});

  final String version;
  final XrayDemo xray;

  @override
  Component build(BuildContext context) {
    return DocsLayout(
      page: .concepts,
      version: version,
      title: 'Concepts',
      description:
          'How Marionette connects an agent to a running Flutter app, how '
          'the agent sees a screen, how it picks a target, and where '
          'Marionette fits next to Patrol and the Flutter MCP server.',
      lead:
          'The few ideas that explain every tool: what the agent sees, how it '
          'picks a target, and why the app runs in debug.',
      toc: _toc,
      children: [
        DocSection(
          id: 'how',
          heading: 'How it works',
          children: [
            const Flow(
              nodes: [
                FlowNode('Agent', 'calls `tap(key: "save")`'),
                FlowNode(
                  'Bridge',
                  'translates it into a VM service call',
                  accent: true,
                ),
                FlowNode(
                  'Binding',
                  'runs `ext.flutter.marionette.tap` in the app',
                  accent: true,
                ),
                FlowNode('App', 'gets a real pointer event'),
              ],
              links: ['MCP or shell', 'VM service', 'gesture'],
            ),
            p(
              rich(
                '`MarionetteBinding` registers a set of VM service extensions '
                'in your app. On `connect`, the bridge checks that the app '
                'runs the same Marionette version. From then on every tool '
                'call becomes one extension call: the app performs the action '
                'and answers with a short result, which goes back to the '
                'agent.',
              ),
            ),
            const p([
              .text(
                'Gestures are dispatched as pointer events, so the app reacts '
                'the way it would to a finger: hit tests, gesture arenas and '
                'focus all apply. Nothing in your widgets changes.',
              ),
            ]),
          ],
        ),
        DocSection(
          id: 'seeing',
          heading: 'How the agent sees a screen',
          children: [
            p(
              rich(
                '`get_interactive_elements` walks the widget tree and returns '
                'a flat list in tree order: every widget a user can act on, '
                'every widget with text, and every `Semantics` with a label '
                'or value. Each entry carries its type, key, text, Semantics '
                'identifier and bounds, so the agent can name a target and '
                'knows where it is.',
              ),
            ),
            p(
              rich(
                'Controls carry their state too, so the agent can tell a '
                'filled form from an empty one: checkboxes and switches '
                'report `value`, radios report `selected`, and text fields '
                'report what was typed as `text`. '
                '[Configure](/docs/configure/#defaults) lists what each one '
                'reports.',
              ),
            ),
            const p([
              .text(
                'Below is one real screen of the example app and the list the '
                'agent received for it. Point at an entry to find it on the '
                'screen; switch to the full payload to see what compaction '
                'leaves out.',
              ),
            ]),
            XRay(xray: xray),
            p(
              rich(
                '`take_screenshots` is the other way to look. It costs far '
                'more context than the list, so agents use it to check '
                'layout or to keep evidence, and the list to act.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'targets',
          heading: 'Choosing a target',
          children: [
            const p([
              .text(
                'Every gesture and text tool matches its target the same way. '
                'From the most to the least stable:',
              ),
            ]),
            const DocTable(
              headers: ['Selector', 'Survives', 'Use it when'],
              rows: [
                [
                  '`key`',
                  'copy changes, translation, refactors',
                  'the widget has a `ValueKey<String>`. Prefer it.',
                ],
                [
                  '`identifier`',
                  'the same, and it is never read aloud',
                  'no key fits: wrap it in `Semantics(identifier:)`.',
                ],
                [
                  '`text`',
                  'nothing that edits or translates the label',
                  'a quick look, or a one-off run.',
                ],
                [
                  '`type`',
                  'only screens with one widget of that type',
                  'the screen has one `PageView` or one `Switch`.',
                ],
                [
                  '`coordinates`',
                  'nothing: any layout or font-scale change',
                  'a diagnostic. If you need them, the widget needs a key.',
                ],
              ],
            ),
            p(
              rich(
                'The first match in the tree wins. When the same key repeats '
                'in identical subtrees, such as grid cells or repeated cards, '
                'add `ancestor_keys`: the keys of the wrappers, outermost '
                'first. Each one is looked up inside the previous one, and a '
                'key with no element fails the call by name instead of '
                'widening the search.',
              ),
            ),
            const CodeBlock(source: _scoped, language: .json, title: 'tap'),
          ],
        ),
        DocSection(
          id: 'compaction',
          heading: 'Compact by default',
          children: [
            p(
              rich(
                'The list never carries style, decoration or colour objects: '
                'only primitive values. On top of that, the default '
                '`CompactionMode.compact` drops rendering details no tool '
                'reads, drops a `Text` element’s duplicated `data`, rounds '
                'bounds to whole logical pixels, and reports `visible` only '
                'when an element is hidden. On the example app that makes '
                'the payload about 65% smaller.',
              ),
            ),
            p(
              rich(
                'Nothing it drops is read by `tap`, `enter_text`, `scroll_to` '
                'or `swipe`. When the agent needs the full dump, it passes '
                '`compaction: "none"` (`--compaction=none` in the CLI), or '
                'the app sets `compaction: CompactionMode.none` as its '
                'default.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'builds',
          heading: 'Debug and profile only',
          children: [
            p(
              rich(
                'The VM service exists in debug and profile builds, never in '
                'release. That is a design choice, not a gap: gate the '
                'binding on `kDebugMode`, or on `!kReleaseMode` to include '
                'profile builds. Both are compile-time constants, so the '
                'release binary contains no Marionette code.',
              ),
            ),
            p(
              rich(
                'Hot reload keeps the app’s state and does not re-run '
                '`main()`. A change to `main()`, to a global singleton or to '
                'the shape of the state needs `hot_restart`, which works when '
                'the app runs under `flutter run`.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'binding',
          heading: 'One binding per process',
          children: [
            p(
              rich(
                'Flutter allows one `WidgetsBinding` per process, and '
                '`MarionetteBinding` is one. If another binding got there '
                'first, `ensureInitialized` throws and names it. Two cases '
                'come up often.',
              ),
            ),
            h3(rich('Tests that call `main()`')),
            p(
              rich(
                '`kDebugMode` is true under `flutter test`, so the test '
                'binding and Marionette collide. Skip Marionette under test, '
                'or give tests their own entrypoint that never initializes '
                'it.',
              ),
            ),
            const CodeBlock(
              source: _skipUnderTest,
              language: .dart,
              title: 'lib/main.dart',
            ),
            const h3([.text('Plugins with their own binding, such as Sentry')]),
            p(
              rich(
                '`SentryFlutter.init` installs a binding before it calls '
                '`appRunner`. Initialized inside `appRunner`, Marionette '
                'throws inside Sentry’s error zone and the app hangs on the '
                'splash screen with no error at all. Initialize Marionette '
                'first; Sentry reuses the binding it finds.',
              ),
            ),
            const CodeBlock(
              source: _sentry,
              language: .dart,
              title: 'lib/main.dart',
            ),
          ],
        ),
        const DocSection(
          id: 'mcp-or-cli',
          heading: 'MCP server or CLI',
          children: [
            p([
              .text(
                'Both bridges drive the same app. Pick the one that fits '
                'your agent and the way you work; most coding agents can '
                'use either.',
              ),
            ]),
            DocTable(
              headers: ['', 'MCP server', 'CLI'],
              rows: [
                [
                  'Package',
                  '`marionette_mcp`',
                  '`marionette_cli`, the `marionette` command',
                ],
                [
                  'Agent needs',
                  'MCP support',
                  'a shell, and the `help-ai` reference',
                ],
                [
                  'Connection',
                  '`connect` once, then calls',
                  '`--uri` per call, or `register` a named instance',
                ],
                [
                  'Custom extensions',
                  'schema-bearing ones become named tools',
                  'not available',
                ],
                ['Video', '—', '`record-video`, with ffmpeg'],
              ],
            ),
            p([
              .text(
                'Both need the same setup in the app, and both write the '
                'same session reports.',
              ),
            ]),
          ],
        ),
        DocSection(
          id: 'fit',
          heading: 'When not to use it',
          children: [
            ul(classes: Prose.checklist.name, [
              li([
                const .text(
                  'A regression suite in CI. Gestures are a best-effort '
                  'simulation of a user, not deterministic instrumentation. '
                  'For tests that pass or fail the same way every time, use ',
                ),
                externalLink(patrolUrl, [const .text('Patrol')]),
                const .text('.'),
              ]),
              li(rich('A release build. The VM service does not exist there.')),
              li(
                rich(
                  'Performance work. Marionette can trigger the interaction '
                  'to profile; measuring it is the job of Flutter DevTools.',
                ),
              ),
              li([
                const .text(
                  'Writing the app: dependencies, analysis and runtime errors '
                  'belong to the ',
                ),
                externalLink(flutterMcpUrl, [
                  const .text('Dart and Flutter MCP server'),
                ]),
                const .text('. Use both.'),
              ]),
            ]),
          ],
        ),
      ],
    );
  }
}
