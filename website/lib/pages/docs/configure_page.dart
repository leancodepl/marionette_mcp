import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/docs_layout.dart';
import 'package:marionette_website/components/section.dart';
import 'package:marionette_website/components/tabs.dart';

const _interactive = '''
MarionetteConfiguration(
  isInteractiveElement: (element) => switch (element.widget) {
    MyButton() || MyTextField() => true,
    MyTile(:final onTap) => onTap != null,
    _ => false,
  },
)''';

const _extractText = '''
MarionetteConfiguration(
  extractText: (element) => switch (element.widget) {
    MyText(:final data) => data,
    MyTextField(:final labelText) => labelText,
    _ => null,
  },
)''';

const _semanticsLabel = '''
// The screen reader says "Volume, 70 percent";
// the agent sees  Type: Semantics, Text: "Volume: 70%".
Semantics(
  label: 'Volume',
  value: '70%',
  child: CustomPaint(painter: _VolumeBarPainter(level: 0.7)),
)''';

const _semanticsIdentifier = '''
// No ValueKey, but a stable target: tap(identifier: "submit_button").
Semantics(
  identifier: 'submit_button',
  child: ElevatedButton(onPressed: _submit, child: const Text('Submit')),
)''';

const _logging = '''
MarionetteBinding.ensureInitialized(
  MarionetteConfiguration(logCollector: LoggingLogCollector()),
);
Logger.root.level = Level.ALL;''';

const _logger = '''
final logCollector = LoggerLogCollector();
MarionetteBinding.ensureInitialized(
  MarionetteConfiguration(logCollector: logCollector),
);
// The collector is also a LogOutput, so one object serves both sides.
final logger = Logger(output: MultiOutput([ConsoleOutput(), logCollector]));''';

const _printCollector = '''
final collector = PrintLogCollector();
MarionetteBinding.ensureInitialized(
  MarionetteConfiguration(logCollector: collector),
);
myLogger.onLog((message) => collector.addLog(message));''';

const _deviceConfig = '''
void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized();
    runApp(const MarionetteDeviceConfig(child: MyApp()));
  } else {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(const MyApp());
  }
}''';

const _extension = '''
registerMarionetteExtension(
  name: 'appNavigation.goToPage',
  description: 'Navigates to a page by name.',
  inputSchema: ExtensionInputSchema(
    properties: {
      'page': ExtensionParam.string(
        description: 'The page to navigate to.',
        enumValues: ['home', 'profile', 'settings'],
      ),
    },
    required: ['page'],
  ),
  callback: (params) async {
    final page = params['page'];
    if (page == null) {
      return MarionetteExtensionResult.invalidParams('Missing page');
    }
    navigateTo(page); // your app's own navigation
    return MarionetteExtensionResult.success({'page': page});
  },
);''';

const _completeMain = '''
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_logging/marionette_logging.dart';

void main() {
  if (!kReleaseMode) {
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(
        // 1. Your interactive widgets.
        isInteractiveElement: (element) => switch (element.widget) {
          MyButton() || MyTextField() => true,
          _ => false,
        },
        // 2. Their text, so the agent can match by label.
        extractText: (element) => switch (element.widget) {
          MyText(:final data) => data,
          _ => null,
        },
        // 3. Logs for get_logs.
        logCollector: LoggingLogCollector(),
        // 4. A report for every run.
        enableSessionReports: true,
      ),
    );
    Logger.root.level = Level.ALL;
    // 5. set_device_config, opted in with one widget.
    runApp(const MarionetteDeviceConfig(child: MyApp()));
  } else {
    runApp(const MyApp());
  }
}''';

const _stopTraversalFor =
    'A composite widget that already reports itself, such as a select whose '
    '`extractText` returns its label: its inner text and buttons would only '
    'repeat it.';

const _stopTraversalNever =
    'Lists, scroll views and whole pages. The agent cannot see, `tap` or '
    '`scroll_to` anything inside them.';

const _toc = [
  ('symptoms', 'Start from the symptom'),
  ('defaults', 'What works as is'),
  ('reference', 'The configuration'),
  ('interactive', 'Interactive widgets'),
  ('text', 'Text'),
  ('semantics', 'Semantics'),
  ('traversal', 'Traversal'),
  ('logs', 'Logs'),
  ('device', 'Device config'),
  ('extensions', 'Custom extensions'),
  ('complete-main', 'A complete main.dart'),
];

/// Docs, page 3: teaching Marionette about an app.
class ConfigurePage extends StatelessComponent {
  const ConfigurePage({required this.version, super.key});

  final String version;

  @override
  Component build(BuildContext context) {
    return DocsLayout(
      page: .configure,
      version: version,
      title: 'Configure',
      description:
          'Teach Marionette your design system: interactive widgets, text '
          'extraction, Semantics, log collection, device config overrides '
          'and custom extensions, with a complete main.dart.',
      lead:
          'Most "it cannot find my button" problems are a missing line of '
          'configuration, not a bug. Find your symptom, add the fix, hot '
          'restart.',
      toc: _toc,
      children: [
        const DocSection(
          id: 'symptoms',
          heading: 'Start from the symptom',
          children: [
            DocTable(
              headers: ['Symptom', 'Fix'],
              rows: [
                [
                  'Your own controls are missing from the listing',
                  'Add them to `isInteractiveElement`.',
                ],
                [
                  '`tap(text:)` cannot find a custom label',
                  'Return its text from `extractText`.',
                ],
                [
                  'Custom-painted text, badges or charts are invisible',
                  'Wrap them in `Semantics(label:, value:)`.',
                ],
                [
                  '`get_logs` explains how to set up a collector',
                  'Set `logCollector`.',
                ],
                [
                  '`set_device_config` answers with setup instructions',
                  'Add `MarionetteDeviceConfig`, then hot restart.',
                ],
                [
                  'Content inside one of your widgets is out of reach',
                  'Remove that widget from `shouldStopTraversalAtElement`.',
                ],
                [
                  'A dialog, picker or WebView is not in the listing',
                  'Drawn by the platform: use the [native lane](/docs/native).',
                ],
              ],
            ),
          ],
        ),
        DocSection(
          id: 'defaults',
          heading: 'What works as is',
          children: [
            p(
              rich(
                "With no configuration, Marionette recognizes Flutter's own "
                'interactive widgets, their subclasses (such as the button '
                '`ElevatedButton.icon` returns) and their generic variants:',
              ),
            ),
            const p([
              code([.text('ButtonStyleButton')]),
              .text(' (Elevated, Filled, Outlined and Text buttons), '),
              code([.text('IconButton')]),
              .text(', '),
              code([.text('FloatingActionButton')]),
              .text(', '),
              code([.text('TextField')]),
              .text(', '),
              code([.text('TextFormField')]),
              .text(', '),
              code([.text('Checkbox')]),
              .text(', '),
              code([.text('Radio')]),
              .text(', '),
              code([.text('Switch')]),
              .text(', '),
              code([.text('Slider')]),
              .text(', '),
              code([.text('DropdownButton')]),
              .text(', '),
              code([.text('PopupMenuButton')]),
              .text(', their list-tile forms, '),
              code([.text('GestureDetector')]),
              .text(' and '),
              code([.text('InkWell')]),
              .text('.'),
            ]),
            const p([
              .text('Text is read from '),
              code([.text('Text')]),
              .text(', '),
              code([.text('RichText')]),
              .text(', '),
              code([.text('EditableText')]),
              .text(' and the text fields. A field’s '),
              code([.text('labelText')]),
              .text(' or '),
              code([.text('hintText')]),
              .text(' is reported as its '),
              code([.text('label')]),
              .text(', so a field without a key still has a name.'),
            ]),
          ],
        ),
        DocSection(
          id: 'reference',
          heading: 'The configuration',
          children: [
            p(
              rich(
                '`MarionetteConfiguration` is the optional argument of '
                '`MarionetteBinding.ensureInitialized`. Every field is '
                'optional, and your callbacks run after the built-in checks: '
                'they extend the defaults, they do not replace them.',
              ),
            ),
            const DocTable(
              headers: ['Field', 'Default', 'Purpose'],
              rows: [
                [
                  '`isInteractiveElement`',
                  '`null`',
                  'Mark your own widgets as interactive.',
                ],
                [
                  '`extractText`',
                  '`null`',
                  'Return the text your widgets show.',
                ],
                [
                  '`logCollector`',
                  '`null`',
                  'Collect the logs `get_logs` returns.',
                ],
                [
                  '`enableSessionReports`',
                  '`false`',
                  'Record each run in `.marionette/sessions/`.',
                ],
                [
                  '`compaction`',
                  '`CompactionMode.compact`',
                  'How much the element listing leaves out.',
                ],
                [
                  '`maxScreenshotSize`',
                  '`Size(2000, 2000)`',
                  'Downscale screenshots to fit; `null` keeps full size.',
                ],
                [
                  '`shouldStopTraversalAtElement`',
                  '`null`',
                  'Skip what lies inside a widget. Rarely needed.',
                ],
              ],
            ),
          ],
        ),
        DocSection(
          id: 'interactive',
          heading: 'Interactive widgets',
          children: [
            p(
              rich(
                'A screen has hundreds of widgets; the agent gets the few it '
                'can act on. Your design system’s widgets are not on the '
                'built-in list, so mark them. The callback gets the '
                '`Element`, so one `switch` over `element.widget` describes '
                'a whole design system.',
              ),
            ),
            const CodeBlock(
              source: _interactive,
              language: .dart,
              title: 'lib/main.dart',
            ),
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'A pattern such as `MySelect()` matches `MySelect<String>` '
                  'and any type argument added later.',
                ),
              ),
              li(
                rich(
                  '`MyButton()` matches every subclass, such as '
                  '`MyPrimaryButton`.',
                ),
              ),
              li(
                rich(
                  'Read fields for per-instance decisions: a `MyTile` is '
                  'interactive only when it has an `onTap`.',
                ),
              ),
              li(
                rich(
                  'Use the element as a `BuildContext` when placement '
                  'matters, e.g. `findAncestorWidgetOfExactType`.',
                ),
              ),
            ]),
          ],
        ),
        DocSection(
          id: 'text',
          heading: 'Text',
          children: [
            p(
              rich(
                '`extractText` does two jobs. Widgets with text appear in the '
                'listing with that text, so the agent knows what each one '
                'shows. And `tap` and `scroll_to` can then match them by '
                'label. `enter_text` targets fields by key or identifier, or '
                'the field focused with a `tap`.',
              ),
            ),
            const CodeBlock(
              source: _extractText,
              language: .dart,
              title: 'lib/main.dart',
            ),
          ],
        ),
        DocSection(
          id: 'semantics',
          heading: 'Semantics',
          children: [
            p(
              rich(
                '`Text.rich` and `RichText` are read without help. For text '
                'that never reaches a `Text` widget, such as `CustomPaint`, '
                '`TextPainter` or `WidgetSpan` content, use the annotation '
                'screen readers already rely on.',
              ),
            ),
            const CodeBlock(
              source: _semanticsLabel,
              language: .dart,
              title: 'label and value',
            ),
            p(
              rich(
                '`label` and `value` are for reading only: the matcher '
                'ignores them, so a `Semantics(label: "Submit")` never steals '
                'a tap from the button inside it. To target a widget without '
                'a key, use `identifier`, which the matcher does read and '
                'screen readers never announce.',
              ),
            ),
            const CodeBlock(
              source: _semanticsIdentifier,
              language: .dart,
              title: 'identifier',
            ),
            p(
              rich(
                '`Text(semanticsIdentifier:)` works the same way. A '
                '`TextSpan.semanticsIdentifier` does not: it lives below the '
                'widget tree, so wrap that run of text in its own '
                '`Semantics(identifier:)` instead.',
              ),
            ),
            const Callout(
              'Screen readers announce `label` as it is. Keep it human: put '
              'machine-readable handles in `identifier`, and raw markup in '
              '`extractText` of a custom widget.',
            ),
          ],
        ),
        DocSection(
          id: 'traversal',
          heading: 'Traversal',
          children: [
            p(
              rich(
                'To list the screen, Marionette walks the widget tree from '
                'the root down. `shouldStopTraversalAtElement` tells it not '
                'to look inside a widget: the widget itself is still listed, '
                'everything below it is not.',
              ),
            ),
            const DocTable(
              headers: ['Use it for', 'Never use it for'],
              rows: [
                [_stopTraversalFor, _stopTraversalNever],
              ],
            ),
            const Callout(
              'Most apps leave it null. On one large app, stopping at scroll '
              'containers hid about a third of the widgets from the agent.',
              kind: .warning,
            ),
          ],
        ),
        DocSection(
          id: 'logs',
          heading: 'Logs',
          children: [
            p(
              rich(
                '`get_logs` returns what the app logged since it started or '
                'since the last hot reload: the quickest proof that a request '
                'fired or an exception was thrown. Pick the adapter for how '
                'your app logs.',
              ),
            ),
            const Tabs(
              name: 'logs',
              groupLabel: 'Logging setup',
              tabs: [
                TabItem('logging', 'logging', [
                  CodeBlock(
                    source: 'flutter pub add marionette_logging',
                    language: .shell,
                    title: 'terminal',
                  ),
                  CodeBlock(
                    source: _logging,
                    language: .dart,
                    title: 'lib/main.dart',
                  ),
                ]),
                TabItem('logger', 'logger', [
                  CodeBlock(
                    source: 'flutter pub add marionette_logger',
                    language: .shell,
                    title: 'terminal',
                  ),
                  CodeBlock(
                    source: _logger,
                    language: .dart,
                    title: 'lib/main.dart',
                  ),
                ]),
                TabItem('print', 'anything else', [
                  CodeBlock(
                    source: _printCollector,
                    language: .dart,
                    title: 'lib/main.dart',
                  ),
                ]),
              ],
            ),
          ],
        ),
        DocSection(
          id: 'device',
          heading: 'Device config',
          children: [
            p(
              rich(
                '`set_device_config` overrides text scale, bold text and '
                'light or dark mode in the running app. It is the one tool '
                'that needs a widget in your tree, because Marionette never '
                'inserts one behind your back. Hot restart after adding it: '
                '`main()` does not re-run on a hot reload.',
              ),
            ),
            const CodeBlock(
              source: _deviceConfig,
              language: .dart,
              title: 'lib/main.dart',
            ),
            p(
              rich(
                '`!kReleaseMode` is a compile-time constant, so neither the '
                'binding nor the widget reaches a release build. Without a '
                'binding the widget builds its child unchanged. When reading '
                'results, note that some Material widgets clamp their own '
                'text scaling, and scales far above 3.0 mostly produce '
                'overflow errors, not signal.',
              ),
            ),
          ],
        ),
        DocSection(
          id: 'extensions',
          heading: 'Custom extensions',
          children: [
            p(
              rich(
                'Give the agent actions the generic tools cannot express: '
                'go to a route by name, seed test data, flip a feature flag. '
                'An extension that declares an `inputSchema` becomes a named '
                'tool with validated arguments, so a bad value is rejected '
                'before it reaches your app.',
              ),
            ),
            const CodeBlock(
              source: _extension,
              language: .dart,
              title: 'lib/main.dart',
            ),
            const DocTable(
              headers: ['Extension name', 'Tool name the agent sees'],
              rows: [
                ['`appNavigation.goToPage`', '`app_navigation_go_to_page`'],
                ['`analytics.flush`', '`analytics_flush`'],
              ],
            ),
            p(
              rich(
                'Tool names are reduced to `[a-z0-9_-]`, the set every LLM '
                'API accepts. Parameters are flat scalars, because arguments '
                'travel over the VM service as strings. An extension without '
                'a schema still works through `call_custom_extension`, and '
                '`list_custom_extensions` shows them all.',
              ),
            ),
          ],
        ),
        const DocSection(
          id: 'complete-main',
          heading: 'A complete main.dart',
          children: [
            CodeBlock(
              source: _completeMain,
              language: .dart,
              title: 'lib/main.dart',
            ),
          ],
        ),
      ],
    );
  }
}
