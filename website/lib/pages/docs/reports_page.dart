import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/docs_layout.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/components/tabs.dart';
import 'package:marionette_website/demo.dart';
import 'package:marionette_website/site.dart';

const _enable = '''
MarionetteBinding.ensureInitialized(
  const MarionetteConfiguration(enableSessionReports: true),
);''';

const _tree = '''
.marionette/                         # writes its own .gitignore
  sessions/
    profile-email-validation-20261006T1326/
      steps.md        # appended by the server, one line per call
      report.md       # written once, at the end, by the agent
      screenshots/
        01.png        # take_screenshots(inline: false)''';

const _template = '''
Marionette · <flow> — <VERDICT>: <reason, a few words>
✓ <what worked, comma-separated>
✗ [<type>] <finding, one line>        (up to 5)
∅ Not covered: <what> — <why>
→ <session>/report.md · <N> steps, <M> screenshots''';

const _fail = '''
Marionette · User Profile — FAIL: 2 bugs
✓ Profile view, edit form
✗ [bug] Date of birth accepts future dates — no validation
✗ [bug] Save does not persist — changes lost after restart
→ .marionette/sessions/user-profile-20260922T1412/report.md · 14 steps, 3 screenshots''';

const _suspect = '''
Marionette · Settings — SUSPECT: theme toggle may not persist
✓ Notification toggles, language picker
✗ [suspicion] Dark mode toggle reverts to light after hot_restart
∅ Not covered: account deletion, data export — out of scope for this run
→ .marionette/sessions/settings-20260922T1601/report.md · 9 steps, 2 screenshots''';

const _blocked = '''
Marionette · Password reset — BLOCKED: reset email never arrives
✓ Request form, validation messages
✗ [blocker] "Send reset link" succeeds but no email is logged after 3 attempts
∅ Not covered: setting a new password — the flow cannot get past the email
→ .marionette/sessions/password-reset-20260922T1601/report.md · 11 steps, 1 screenshot''';

const _failReport = '''
🐛 Marionette report — 2 findings · User Profile
Tested: profile view, edit form, save flow (14 steps, 3 screenshots)

1. 🐛 [bug] Date of birth accepts future dates — no validation
   Repro: Profile → Edit → DOB = 2099-01-01 → Save
   Evidence: step 9, log "saved dob=2099-01-01"

2. 🐛 [bug] Save does not persist — changes lost after restart
   Repro: Profile → Edit → Name = "X" → Save → hot_restart → Profile
   Evidence: step 14, screenshots/02-after-restart.png''';

const _patrolPrompt = '''
Write a Patrol test from .marionette/sessions/<run>/steps.md and report.md:
the same steps with the same keys, and the checks from the report as
expectations.''';

const _toc = [
  ('enable', 'Turn them on'),
  ('folder', 'One run, one folder'),
  ('steps', 'steps.md'),
  ('report', 'report.md'),
  ('verdict', 'The closing message'),
  ('share', 'Sharing a report'),
  ('patrol', 'From a run to a Patrol test'),
];

/// Docs, page 5: what a run leaves behind, and why it can be trusted.
class ReportsPage extends StatelessComponent {
  const ReportsPage({required this.version, required this.loop, super.key});

  final String version;

  /// The recorded run, whose real steps and report this page shows.
  final LoopDemo loop;

  @override
  Component build(BuildContext context) {
    final steps = [for (final beat in loop.beats) beat.step].join('\n');
    return DocsLayout(
      page: .reports,
      version: version,
      title: 'Reports',
      description:
          'Session reports: the folder each run gets, the steps.md the '
          'server writes, the report.md the agent writes, and the verdict '
          'it closes with.',
      lead:
          'An agent’s summary is a claim. A session report is a claim with '
          'its evidence next to it: the server logs every call, and the '
          'agent writes the report from that log.',
      toc: _toc,
      children: [
        DocSection(
          id: 'enable',
          heading: 'Turn them on',
          children: [
            p(
              rich(
                'Session reports are off by default; then nothing is written '
                'to disk and screenshots only come back inline. One flag '
                'turns them on:',
              ),
            ),
            const CodeBlock(
              source: _enable,
              language: .dart,
              title: 'lib/main.dart',
            ),
          ],
        ),
        DocSection(
          id: 'folder',
          heading: 'One run, one folder',
          children: [
            p(
              rich(
                'Every `connect` opens a fresh folder, named after the '
                '`session_title` the agent passes and the time. A run is '
                'never resumed: an interrupted one is abandoned, and the next '
                '`connect` starts over, so a report can never be overwritten '
                'by a later, unrelated run.',
              ),
            ),
            const CodeBlock(
              source: _tree,
              language: .console,
              title: 'project root',
              copyText: '',
            ),
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'Where: the `session_dir` argument of `connect` '
                  '(`--session-dir` in the CLI), else the '
                  '`MARIONETTE_SESSION_DIR` variable, else the working '
                  'directory.',
                ),
              ),
              li(
                rich(
                  'The 20 most recently used folders are kept. A folder with '
                  'a `report.md` is never pruned.',
                ),
              ),
              li(
                rich(
                  'If the folder cannot be created, the connection still '
                  'works, just without a record.',
                ),
              ),
            ]),
          ],
        ),
        DocSection(
          id: 'steps',
          heading: 'steps.md',
          children: [
            p(
              rich(
                'The server appends one line per tool call as it happens: '
                'the tool, a short selector and the outcome. The agent never '
                'writes to it, so a step cannot be skipped or improved after '
                'the fact. These are the real lines of the run on the home '
                'page:',
              ),
            ),
            CodeBlock(
              source: steps,
              language: .console,
              title: 'steps.md',
              copyText: '',
            ),
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'No payloads: a call that returns app data, such as '
                  '`get_interactive_elements` or `get_logs`, is logged as '
                  '`ok`.',
                ),
              ),
              li(
                rich(
                  'Typed text is logged as its length, `input_len=12`. For a '
                  'field whose key looks like a password, PIN, token, secret '
                  'or CVV, even the length is withheld.',
                ),
              ),
              li(
                rich(
                  'A VM service URI is cut to `ws://host:port`: its path '
                  'holds a live debug-access token.',
                ),
              ),
              li(
                rich(
                  'A crash in the app is logged as the exception and a few '
                  'stack frames, not the raw error payload.',
                ),
              ),
            ]),
            p(
              rich(
                'For evidence, the agent calls `take_screenshots(inline: '
                'false)`: the image goes to `screenshots/` and the agent gets '
                'its path instead of the pixels, which saves context.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'report',
          heading: 'report.md',
          children: [
            p(
              rich(
                'The agent writes `report.md` once, at the end, or when it '
                'stops early and says why. `disconnect` reminds it, with the '
                'folder’s path. The format is a contract the drive Agent '
                'Skill teaches:',
              ),
            ),
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'The `Tested:` line is counted from `steps.md`, never from '
                  'memory.',
                ),
              ),
              li(
                rich(
                  'Every finding cites a step, a log line or a screenshot. '
                  'Without evidence it is a `[suspicion]`, and says so.',
                ),
              ),
              li(
                rich(
                  'Under six lines per finding: a tag, a summary, a repro '
                  'path, the evidence.',
                ),
              ),
              li(
                rich(
                  'A status icon on the headline and each finding: ✅ clean, '
                  '⚠️ suspicion, 🐛 bug, ➖ not covered.',
                ),
              ),
              li(
                rich(
                  'Written in the language of the prompt; tool names, paths '
                  'and keys stay as they are.',
                ),
              ),
            ]),
            Tabs(
              name: 'report-example',
              groupLabel: 'Example report',
              tabs: [
                TabItem('pass', 'the recorded run', [
                  CodeBlock(
                    source: loop.report,
                    language: .console,
                    title: 'report.md',
                    copyText: '',
                  ),
                ]),
                const TabItem('fail', 'two bugs', [
                  CodeBlock(
                    source: _failReport,
                    language: .console,
                    title: 'report.md · format example',
                    copyText: '',
                  ),
                ]),
              ],
            ),
          ],
        ),
        DocSection(
          id: 'verdict',
          heading: 'The closing message',
          children: [
            p(
              rich(
                'The chat gets a short message, not a second copy of the '
                'report. Its verdict is one of four words, never translated: '
                '`PASS`, `SUSPECT`, `FAIL` or `BLOCKED`. `BLOCKED` wins when '
                'the run could not finish, even if it also found a bug.',
              ),
            ),
            const CodeBlock(
              source: _template,
              language: .console,
              title: 'template',
              copyText: '',
            ),
            Tabs(
              name: 'verdicts',
              groupLabel: 'Verdict',
              tabs: [
                TabItem('pass', 'PASS', [
                  CodeBlock(
                    source: loop.verdict,
                    language: .console,
                    title: 'the recorded run',
                    copyText: '',
                  ),
                ]),
                const TabItem('fail', 'FAIL', [
                  CodeBlock(
                    source: _fail,
                    language: .console,
                    title: 'format example',
                    copyText: '',
                  ),
                ]),
                const TabItem('suspect', 'SUSPECT', [
                  CodeBlock(
                    source: _suspect,
                    language: .console,
                    title: 'format example',
                    copyText: '',
                  ),
                ]),
                const TabItem('blocked', 'BLOCKED', [
                  CodeBlock(
                    source: _blocked,
                    language: .console,
                    title: 'format example',
                    copyText: '',
                  ),
                ]),
              ],
            ),
          ],
        ),
        DocSection(
          id: 'share',
          heading: 'Sharing a report',
          children: [
            p(
              rich(
                'The first session in a project writes `.marionette/'
                '.gitignore`, so reports stay out of version control without '
                'setup. Committing one, for example to attach it to a pull '
                'request, is a deliberate choice: copy the folder out, or '
                'remove that file.',
              ),
            ),
            p(
              rich(
                'The CLI writes the same records. Each command is its own '
                'process, so each one gets its own folder; `--session` only '
                'names it.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'patrol',
          heading: 'From a run to a Patrol test',
          children: [
            p([
              ...rich(
                'A run that passed is a test script already: `steps.md` '
                'lists every action with the key it targeted, and '
                '`report.md` says what was checked. Give both to your agent '
                'in a project with ',
              ),
              externalLink(patrolUrl, [const .text('Patrol')]),
              const .text(
                ', and ask for a test that replays the run. Marionette '
                'explores the app; Patrol keeps the result in CI.',
              ),
            ]),
            p(
              rich(
                'The `marionette-flutter-to-patrol` skill, from '
                '[Add the Agent Skills](/docs/#skill), teaches the agent the '
                'rest: which widgets need keys, how each step maps to Patrol, '
                'and which assertions the report implies.',
              ),
            ),
            const CodeBlock(
              source: _patrolPrompt,
              language: .console,
              title: 'prompt',
            ),
          ],
        ),
      ],
    );
  }
}
