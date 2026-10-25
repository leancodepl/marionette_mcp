import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/clients.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/docs_layout.dart';
import 'package:marionette_website/components/docs_widgets.dart';
import 'package:marionette_website/components/faq.dart';
import 'package:marionette_website/components/landing_sections.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/site.dart';

const _runOutput = r'''
$ flutter run
…
A Dart VM Service on sdk gphone64 x86 64 is available at: http://127.0.0.1:9101/V3N5aBc=/
The Flutter DevTools debugger and profiler on sdk gphone64 x86 64 is available at:
http://127.0.0.1:9101/V3N5aBc=/devtools/?uri=ws://127.0.0.1:9101/V3N5aBc=/ws''';

const _exampleCommands = r'''
$ git clone https://github.com/leancodepl/marionette_mcp
$ cd marionette_mcp/example
$ flutter run''';

const _skillInstall = r'''
$ flutter pub add marionette_flutter   # if it is not a dependency yet
$ dart run skills@ get''';

const _examplePrompt = '''
Connect to <the ws:// URI from flutter run>. Open the Custom Widgets screen
and list what you see. Which of the design-system widgets can you tap?''';

const _toc = [
  ('how', 'How it fits together'),
  ('add', 'Add the package'),
  ('bridge', 'Give your agent the tools'),
  ('skill', 'Add the Agent Skill'),
  ('run', 'Run the app'),
  ('prompt', 'The first prompt'),
  ('example', 'Try the example app'),
  ('working', 'Is it working?'),
  ('faq', 'FAQ'),
];

/// Docs, page 1: from nothing to the first prompt.
class StartPage extends StatelessComponent {
  const StartPage({required this.version, super.key});

  final String version;

  @override
  Component build(BuildContext context) {
    return DocsLayout(
      page: .start,
      version: version,
      title: 'Start',
      description:
          'Set up Marionette in a Flutter app and give your AI agent its '
          'tools: the package, the binding, the MCP server or CLI, the '
          'Agent Skill and the first prompt.',
      lead:
          'Five minutes from a plain Flutter app to an agent that taps '
          'through it. This page covers apps built from Material widgets; '
          'a custom design system adds one step, in '
          '[Configure](/docs/configure/#interactive).',
      toc: _toc,
      structuredData: [faqStructuredData()],
      children: [
        const DocSection(
          id: 'how',
          heading: 'How it fits together',
          children: [
            p([
              .text(
                'Marionette has two halves. A package in your app opens it '
                'to the agent through the Dart VM service, the same channel '
                'Flutter DevTools uses. A bridge, the MCP server or the CLI, '
                'turns the agent’s tool calls into actions in the app.',
              ),
            ]),
            Flow(
              nodes: [
                FlowNode('Your agent', 'Claude Code, Cursor, Codex, …'),
                FlowNode(
                  'The bridge',
                  '`marionette_mcp`, or the `marionette` CLI',
                  accent: true,
                ),
                FlowNode(
                  'Your app, in debug',
                  '`marionette_flutter` and its binding',
                  accent: true,
                ),
              ],
              links: ['MCP or shell', 'VM service'],
            ),
            p([
              .text(
                'The app always needs the package. For the bridge, pick '
                'either one: both see and drive the app, and both write the '
                'same session reports.',
              ),
            ]),
          ],
        ),
        DocSection(
          id: 'add',
          heading: 'Add the package',
          children: [
            p(
              rich(
                'Add `marionette_flutter` to the app, then initialize '
                '`MarionetteBinding` in `main()`, in debug builds only. For '
                'standard Material widgets the defaults are enough.',
              ),
            ),
            const CodeBlock(
              source: installCommand,
              language: .shell,
              title: 'terminal',
            ),
            const CodeBlock(
              source: bindingSnippet,
              language: .dart,
              title: 'lib/main.dart',
            ),
            const Callout(
              '`MarionetteBinding` must be the only binding in the process. '
              'A test that calls `main()`, or a plugin such as Sentry that '
              'installs its own binding first, breaks this rule. See '
              '[Concepts](/docs/concepts/#binding) for the fix.',
              kind: .warning,
            ),
          ],
        ),
        DocSection(
          id: 'bridge',
          heading: 'Give your agent the tools',
          children: [
            const p([
              .text(
                'Pick the bridge you prefer. Both see and drive the app, and '
                'both write the same session reports.',
              ),
            ]),
            const h3([.text('MCP server')]),
            p(
              rich(
                'Your agent calls Marionette’s tools. Install the server '
                'once, then register it with your agent.',
              ),
            ),
            const CodeBlock(
              source: mcpInstallCommand,
              language: .shell,
              title: 'terminal',
            ),
            clientTabs(name: 'client-docs'),
            p(
              rich(
                'Prefer a dev dependency to a global tool? Run '
                '`dart pub add dev:marionette_mcp`, and register '
                '`dart run marionette_mcp` as the server command.',
              ),
            ),
            const Callout(
              'For a Flutter 3.27 app that uses `flutter_test`, install the '
              'server globally. The test SDK and current MCP server require '
              'incompatible dependency versions in a shared app graph.',
            ),
            const h3([.text('CLI')]),
            p(
              rich(
                'Your agent runs `marionette` commands in its shell. Install '
                'the CLI once; the Agent Skill below teaches the agent its '
                'commands.',
              ),
            ),
            const CodeBlock(
              source: cliInstallCommand,
              language: .shell,
              title: 'terminal',
            ),
          ],
        ),
        DocSection(
          id: 'skill',
          heading: 'Add the Agent Skill',
          children: [
            p([
              const code([.text('marionette_flutter')]),
              const .text(' ships an '),
              externalLink('https://agentskills.io', [
                const .text('Agent Skill'),
              ]),
              ...rich(
                ': a `SKILL.md` that teaches an agent to prepare an app for '
                'Marionette and drive it, with either bridge. This '
                'documentation then does not have to be in its context. '
                'Dart’s package skills tooling installs it into the folder '
                'your agent reads.',
              ),
            ]),
            const Terminal(transcript: _skillInstall, title: 'terminal'),
            p(
              rich(
                'Without the Dart toolchain, `npx skills add '
                'leancodepl/marionette_mcp` reads it straight from GitHub. '
                'Run the install again after upgrading the package.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'run',
          heading: 'Run the app',
          children: [
            p(
              rich(
                'Start the app in debug mode. Among the first lines, '
                '`flutter run` prints the VM service URI. The agent needs the '
                '`ws://…/ws` part.',
              ),
            ),
            const Terminal(transcript: _runOutput, title: 'flutter run'),
            p(
              rich(
                'Paste that URI into the prompt yourself, or ask the agent to '
                'run the app: it starts `flutter run`, reads the URI from the '
                'output, and connects.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'prompt',
          heading: 'The first prompt',
          children: [
            const p([.text('Give the agent a task:')]),
            firstPromptTabs(name: 'prompt-docs'),
            p(
              rich(
                'The agent calls `connect`, then `get_interactive_elements` '
                'to see the screen, then `tap` and `enter_text` with the keys '
                'or the text it found, then `get_logs` for the proof. That is '
                'the whole loop: look, act, look again.',
              ),
            ),
            p(
              rich(
                'For a real task, name the screen, the precondition and the '
                'goal. [Drive](/docs/drive/#prompts) has prompts for common '
                'jobs.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'example',
          heading: 'Try the example app first',
          children: [
            p([
              const .text('The repository has an '),
              externalLink(exampleUrl, [const .text('example app')]),
              const .text(
                ' that is already set up: a custom design system with its '
                'configuration, log collection, session reports, device '
                'config and a custom navigation extension. It is the lowest '
                'risk first run.',
              ),
            ]),
            const Callout(
              'Use the Flutter version pinned in '
              '[`.fvmrc`]($repoUrl/blob/main/.fvmrc) for this checkout. The '
              'example resolves the full repository workspace. Flutter 3.27 '
              'apps using the binding with a separately installed server '
              'remain supported.',
            ),
            const Terminal(transcript: _exampleCommands, title: 'terminal'),
            const CodeBlock(
              source: _examplePrompt,
              language: .console,
              title: 'prompt',
            ),
          ],
        ),
        DocSection(
          id: 'working',
          heading: 'Is it working?',
          children: [
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  '`connect` answers with a success message. A version '
                  'mismatch means `marionette_mcp` and `marionette_flutter` '
                  'differ: upgrade both.',
                ),
              ),
              li(
                rich(
                  '`get_interactive_elements` lists your buttons and fields. '
                  'If your own widgets are missing, the configuration in '
                  '[Configure](/docs/configure/#symptoms) is the fix, not a '
                  'bug.',
                ),
              ),
              li(
                rich(
                  '`tap` changes the screen, and a second '
                  '`get_interactive_elements` shows the new one.',
                ),
              ),
              li(
                rich(
                  '`get_logs` returns lines. If it explains how to enable a '
                  'log collector instead, wire one up in '
                  '[Configure](/docs/configure/#logs).',
                ),
              ),
            ]),
          ],
        ),
        const DocSection(id: 'faq', heading: 'FAQ', children: [Faq()]),
      ],
    );
  }
}
