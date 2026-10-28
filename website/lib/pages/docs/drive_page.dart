import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/docs_layout.dart';
import 'package:marionette_website/components/docs_widgets.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/site.dart';

const _weakPrompt = '''
Test the profile screen.''';

const _strongPrompt = '''
Connect to ws://127.0.0.1:9101/V3N5aBc=/ws. Assume the user is logged in.
On Profile, a malformed email must show an error and keep Submit
(key: submit_button) disabled; a valid one must submit.''';

const _cliSession = r'''
$ marionette register shop ws://127.0.0.1:9101/V3N5aBc=/ws
$ marionette -i shop get-interactive-elements
$ marionette -i shop tap --key checkout_button
$ marionette -i shop enter-text --key promo_field --input "SPRING"
$ marionette -i shop get-logs
$ marionette -i shop record-video -o checkout.webm -d 10''';

const _prompts = [
  PromptExample(
    id: 'prompt-feature',
    intent: 'Verify a feature you just built',
    prompt:
        'I implemented the Forgot Password screen. Go to Login, tap "Forgot '
        'password", enter a valid email, submit, and check the logs that the '
        'reset request fired.',
    outcome: 'A verdict with the log line as its evidence.',
  ),
  PromptExample(
    id: 'prompt-reproduce',
    intent: 'Reproduce a bug from a ticket',
    prompt:
        'Reproduce the ticket: on Settings, "Clear cache" does nothing. '
        'Follow the steps, save a screenshot, and read the logs. Do not '
        'change any code yet.',
    outcome: 'Evidence that the bug is real before anyone edits the code.',
  ),
  PromptExample(
    id: 'prompt-fix',
    intent: 'Fix it, then prove it',
    prompt:
        'Fix the bug you just reproduced, hot reload, and replay the same '
        'steps. Tell me whether the symptom is gone, not just a nearby one.',
    outcome: 'The same steps before and after the fix, in one `steps.md`.',
  ),
  PromptExample(
    id: 'prompt-smoke',
    intent: 'Walk a refactor',
    prompt:
        'I refactored the routing. Open every bottom-nav tab, confirm each '
        'screen loads, and check the logs for exceptions after each one.',
    outcome: 'Each screen checked, each with its log check.',
  ),
  PromptExample(
    id: 'prompt-a11y',
    intent: 'Sweep text scale and bold text',
    prompt:
        'On Checkout, set text scale to 2.0, then 3.0 with bold text. After '
        'each, take a screenshot and check the logs for overflow errors.',
    outcome:
        'Overflow errors per scale, with screenshots. Needs '
        '`MarionetteDeviceConfig` in the app.',
  ),
  PromptExample(
    id: 'prompt-form',
    intent: 'Check a form',
    prompt:
        'Check the Profile form: a malformed email must show an error and '
        'keep Submit disabled, and a valid one must submit.',
    outcome:
        'The run on the home page. Error text is read from a screenshot: '
        'the listing reports a field’s label, not its error.',
  ),
  PromptExample(
    id: 'prompt-pr',
    intent: 'Evidence for a pull request',
    prompt:
        'Save screenshots of Settings in light and dark mode to the session '
        'for the pull request.',
    outcome:
        '`screenshots/01.png` and `02.png`, next to the session’s '
        '`report.md`.',
  ),
  PromptExample(
    id: 'prompt-explore',
    intent: 'Map an unfamiliar app',
    prompt:
        'List the custom extensions this app offers, use them to open each '
        'page once, and tell me what each page is for.',
    outcome: 'A map of the app, without reading its code.',
  ),
];

const _toc = [
  ('anatomy', 'A good prompt'),
  ('prompts', 'Prompts for common jobs'),
  ('practices', 'How the agent should work'),
  ('tools', 'Every tool'),
  ('cli', 'The CLI'),
];

/// Docs, page 4: what to ask for, and how the agent goes about it.
class DrivePage extends StatelessComponent {
  const DrivePage({required this.version, super.key});

  final String version;

  @override
  Component build(BuildContext context) {
    return DocsLayout(
      page: .drive,
      version: version,
      title: 'Drive',
      description:
          'Prompts for common jobs, how a Marionette agent should work, and '
          'every tool with its MCP name and CLI command.',
      lead:
          'Marionette sees and acts; it does not know your product. A prompt '
          'that names the screen, the precondition and the goal is most of '
          'a good run.',
      toc: _toc,
      children: [
        DocSection(
          id: 'anatomy',
          heading: 'A good prompt',
          children: [
            p(
              rich(
                'Give the agent what the screen cannot tell it: where to go, '
                'what to assume, what “works” means, and which keys to use. '
                'The report comes on its own when session reports are on.',
              ),
            ),
            const CodeBlock(
              source: _weakPrompt,
              language: .console,
              title: 'too little',
              copyText: '',
            ),
            const CodeBlock(
              source: _strongPrompt,
              language: .console,
              title: 'enough',
            ),
          ],
        ),
        DocSection(
          id: 'prompts',
          heading: 'Prompts for common jobs',
          children: [
            p(
              rich(
                'Each prompt assumes a connected agent: add the `ws://` URI '
                'from `flutter run`, or ask the agent to run the app first. '
                'Replace the screen names with yours.',
              ),
            ),
            const PromptCards(_prompts),
          ],
        ),
        DocSection(
          id: 'practices',
          heading: 'How the agent should work',
          children: [
            p(
              rich(
                'The drive [Agent Skill](/docs/#skill) teaches these; they '
                'are also the checklist for reading a run.',
              ),
            ),
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'Look before acting: `get_interactive_elements` on every new '
                  'screen, not a guess from the source code.',
                ),
              ),
              li(
                rich(
                  'Target by `key`, then `identifier`, then `text`. '
                  'Coordinates are a diagnostic: needing them means the '
                  'widget needs a key.',
                ),
              ),
              li(
                rich(
                  'Confirm side effects in `get_logs`. A tap that looks right '
                  'is not proof that the request fired.',
                ),
              ),
              li(
                rich(
                  'Treat "element not found" as a setup gap first: an '
                  'unconfigured widget, or painted content without '
                  '`Semantics`.',
                ),
              ),
              li(
                rich(
                  'Use `take_screenshots(inline: false)` for evidence: it '
                  'saves the image to the session instead of spending '
                  'context on it.',
                ),
              ),
              li(
                rich(
                  'A flow that is flaky every time needs a clearer key or a '
                  'simpler hit target, not more retries.',
                ),
              ),
            ]),
          ],
        ),
        const DocSection(
          id: 'tools',
          heading: 'Every tool',
          children: [
            DocTable(
              headers: ['MCP tool', 'CLI command', 'What it does'],
              rows: [
                [
                  '`connect`',
                  '`--uri`, or `register` + `-i`',
                  'Attach to the app; opens a session when reports are on.',
                ],
                [
                  '`disconnect`',
                  '—',
                  'Detach; names the session folder for `report.md`.',
                ],
                [
                  '`get_interactive_elements`',
                  '`get-interactive-elements`',
                  'List what is on screen; `ancestor_keys`, `compaction`.',
                ],
                [
                  '`take_screenshots`',
                  '`take-screenshots`',
                  'Capture every view; `inline: false` saves to the session.',
                ],
                [
                  '`get_logs`',
                  '`get-logs`',
                  'Logs since start or the last hot reload.',
                ],
                [
                  '`tap`',
                  '`tap`',
                  'By key, identifier, text, type or coordinates.',
                ],
                [
                  '`double_tap`, `long_press`',
                  '`double-tap`, `long-press`',
                  'With a delay or a duration.',
                ],
                [
                  '`secondary_tap`',
                  '`secondary-tap`',
                  'Right click, on desktop.',
                ],
                [
                  '`swipe`, `pinch_zoom`',
                  '`swipe`, `pinch-zoom`',
                  'Pages, dismissibles, drawers, maps, images.',
                ],
                [
                  '`scroll_to`',
                  '`scroll-to`',
                  'Scroll until a target is built and visible.',
                ],
                [
                  '`press_back_button`',
                  '`press-back-button`',
                  'System back, with `Navigator` or `go_router`.',
                ],
                [
                  '`enter_text`',
                  '`enter-text`',
                  'Set a field by key, identifier, or the focused field.',
                ],
                [
                  '`press_key`',
                  '`press-key`',
                  'A real key event: enter, tab, escape, shortcuts.',
                ],
                [
                  '`set_device_config`',
                  '`set-device-config`',
                  'Text scale, bold text, light or dark.',
                ],
                [
                  '`list_custom_extensions`, `call_custom_extension`',
                  '—',
                  "The app's own actions, and named tools from schemas.",
                ],
                [
                  '`hot_reload`, `hot_restart`',
                  '`hot-reload`, `hot-restart`',
                  'Apply code changes, keeping or resetting state.',
                ],
                [
                  '—',
                  '`record-video`',
                  'A WebM clip of the app; needs ffmpeg.',
                ],
              ],
            ),
            Callout(
              '`press_key` reaches shortcuts, focus and submit on every '
              'platform, but editing inside a text field with keys works on '
              'desktop and web only. On iOS and Android the keyboard owns the '
              'field, so change its value with `enter_text`.',
            ),
          ],
        ),
        DocSection(
          id: 'cli',
          heading: 'The CLI',
          children: [
            p(
              rich(
                '`marionette_cli` installs the `marionette` command: the '
                'same actions as the MCP server, as shell commands. It needs '
                'the same setup in the app. `marionette help-ai` prints a '
                'reference written for agents: have the agent read it once, '
                'or save it as a rule.',
              ),
            ),
            const CodeBlock(
              source: '$cliInstallCommand\nmarionette help-ai',
              language: .shell,
              title: 'terminal',
            ),
            p(
              rich(
                'Pass `--uri` for a one-off command, or `register` the app '
                'under a name once and use `-i`. `list`, `doctor` and '
                '`unregister --stale` manage the instances, `--timeout` '
                'raises the 5 second default, and `marionette mcp` runs the '
                'MCP server itself.',
              ),
            ),
            const Terminal(transcript: _cliSession, title: 'a CLI session'),
            const Callout(
              'With session reports on, each CLI command is its own process '
              'and writes its own session folder. The MCP server writes one '
              'folder per connection.',
            ),
          ],
        ),
      ],
    );
  }
}
