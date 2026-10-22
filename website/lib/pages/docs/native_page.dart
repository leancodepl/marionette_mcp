import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:marionette_website/components/code_block.dart';
import 'package:marionette_website/components/docs_layout.dart';
import 'package:marionette_website/components/docs_widgets.dart';
import 'package:marionette_website/components/section.dart';

const _wdaBuild = r'''
git clone https://github.com/appium/WebDriverAgent.git
cd WebDriverAgent
xcodebuild build-for-testing \
  -project WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -destination 'platform=iOS Simulator,id=<UDID>'
export MARIONETTE_WDA_XCTESTRUN=/path/to/WebDriverAgentRunner_*.xctestrun''';

const _resetPermission = '''
adb shell pm revoke <package> <permission>
xcrun simctl privacy <udid> reset all <bundle id>''';

const _cliSession = r'''
$ marionette native-connect --platform android
$ marionette native-wait-for --text "Allow" --timeout-ms 5000
$ marionette native-tap --text "Allow"
$ marionette native-get-elements --clickable-only
$ marionette native-take-screenshot -o dialog.png
$ marionette native-disconnect''';

const _prompts = [
  PromptExample(
    id: 'prompt-permission',
    intent: 'Allow a permission',
    prompt:
        'Tap "Add photo" on Profile. When the system asks for photo access, '
        'allow it with the native tools, then check that the picker opened.',
    outcome: 'The dialog answered natively, and the picker seen behind it.',
  ),
  PromptExample(
    id: 'prompt-picker',
    intent: 'Pick a file',
    prompt:
        'On Documents, tap "Upload", pick report.pdf in the system file '
        'picker, and check that the file name shows up in the app.',
    outcome: 'A file chosen in system UI, verified back in Flutter.',
  ),
  PromptExample(
    id: 'prompt-webview',
    intent: 'Fill a WebView',
    prompt:
        'Open Terms, scroll the WebView to the checkbox, check it, tap '
        '"Accept", and confirm the app moves on to Home.',
    outcome: 'WebView content driven through the native tree.',
  ),
  PromptExample(
    id: 'prompt-notification',
    intent: 'Open a notification',
    prompt:
        'Trigger the order notification, send the app to the background, '
        'open the notification from the system list, and check that Order '
        'details opens.',
    outcome: 'The notification read and opened from the shade.',
  ),
];

const _toc = [
  ('when', 'When to switch lanes'),
  ('sees', 'What each lane sees'),
  ('setup', 'Set up the device'),
  ('connect', 'Connect'),
  ('prompts', 'Prompts'),
  ('practices', 'How the agent should work'),
  ('permissions', 'Permission dialogs'),
  ('notifications', 'Notifications'),
  ('tools', 'Every native tool'),
  ('reports', 'In session reports'),
  ('symptoms', 'Start from the symptom'),
];

/// Docs, page 5: the native lane, for UI the Flutter tree cannot see.
class NativePage extends StatelessComponent {
  const NativePage({required this.version, super.key});

  final String version;

  @override
  Component build(BuildContext context) {
    return DocsLayout(
      page: .native,
      version: version,
      title: 'Native lane',
      description:
          'Permission dialogs, pickers, WebViews, native views and '
          'notifications: the native tools that reach UI outside the Flutter '
          'widget tree, on Android and the iOS Simulator.',
      lead:
          'Some of what a user sees is drawn by the platform, not by Flutter. '
          'The native lane drives it through the device’s own UI automation, '
          'next to the Flutter tools.',
      toc: _toc,
      children: [
        DocSection(
          id: 'when',
          heading: 'When to switch lanes',
          children: [
            p(
              rich(
                'The Flutter tools (the Flutter lane) see the widget tree. '
                'The `native_*` tools (the native lane) talk to UIAutomator2 '
                'on Android and WebDriverAgent on the iOS Simulator, and see '
                'everything on screen: permission dialogs, system alerts, '
                'pickers and share sheets, WebView content, native controls '
                'in a platform view, native screens and the notification '
                'shade.',
              ),
            ),
            p(
              rich(
                'Prefer the Flutter lane for widgets in the app. Switch when '
                'the target is not in the Flutter tree, and switch back once '
                'the app is in front again. While system UI covers the app, '
                '`get_interactive_elements` starts with a warning that the '
                'app is not in front: the widgets it lists are underneath and '
                'a tap on them does nothing.',
              ),
            ),
            const Callout(
              'An alert or sheet that the app itself shows on iOS leaves the '
              'app in front, so it gives no warning. If a Flutter action has '
              'no effect there, check `native_get_elements`.',
            ),
          ],
        ),
        const DocSection(
          id: 'sees',
          heading: 'What each lane sees',
          children: [
            DocTable(
              headers: ['UI', 'Flutter lane', 'Native lane'],
              rows: [
                ['Widgets of the app', 'Yes', 'Prefer the Flutter lane'],
                ['Permission dialogs, system alerts', 'No', 'Read, tap'],
                ['Photo and file pickers, share sheet', 'No', 'Read, tap'],
                ['WebView content', 'No', 'Fields, buttons, links'],
                ['Native controls in a platform view', 'No', 'Read, tap, type'],
                ['Native screens', 'No', 'Read, tap, type'],
                ['Notifications', 'No', 'In the system list'],
                ['Camera preview, map, video', 'No', 'Only controls around'],
                ['Software keyboard', 'No', 'iOS: keys; Android: hidden'],
              ],
            ),
          ],
        ),
        DocSection(
          id: 'setup',
          heading: 'Set up the device',
          children: [
            p(
              rich(
                'The app needs nothing new: the native lane does not go '
                'through `MarionetteBinding`. The device does.',
              ),
            ),
            const h3([.text('Android')]),
            p(
              rich(
                '`adb` on `PATH` and a device or emulator that `adb devices` '
                'lists as `device`. On the first connect Marionette downloads '
                'the pinned UIAutomator2 APKs, checks their SHA-256 and '
                'installs them; later connects reuse them. '
                '`MARIONETTE_UIA2_SERVER_APK` and `MARIONETTE_UIA2_TEST_APK` '
                'point at local copies, `MARIONETTE_UIA2_PORT` fixes the '
                'local port.',
              ),
            ),
            const h3([.text('iOS Simulator')]),
            p(
              rich(
                'macOS with Xcode and a booted simulator; physical iPhones '
                'are not supported yet. WebDriverAgent is built once, for the '
                'simulator runtime you use, and Marionette is pointed at the '
                'build. It also finds a build copied to '
                '`~/.cache/marionette_mcp/wda/`, and reuses a WebDriverAgent '
                'already running for the simulator.',
              ),
            ),
            const CodeBlock(
              source: _wdaBuild,
              language: .shell,
              title: 'terminal',
            ),
          ],
        ),
        DocSection(
          id: 'connect',
          heading: 'Connect',
          children: [
            p(
              rich(
                '`native_connect` with `platform: android` or `ios`, plus '
                '`serial` or `udid` when several devices are attached. It is '
                'separate from `connect`: a run usually uses both. If a '
                'native call later says the device-side server or session is '
                'gone, call `native_connect` again; `native_disconnect` ends '
                'it.',
              ),
            ),
            p(
              rich(
                'In the CLI, `marionette native-connect` starts the '
                'device-side server detached from the CLI, so later '
                '`native-*` commands reuse it without setup, and '
                '`native-disconnect` stops it. `--native-device <name>` names '
                'a connection to drive several devices at once; '
                '`native-sessions` lists them.',
              ),
            ),
            const Terminal(
              transcript: _cliSession,
              title: 'a permission dialog from the CLI',
            ),
            const Callout(
              'UIAutomator2 has one session per Android device. An MCP '
              'server and a CLI on the same device take it from each other: '
              'the CLI opens a new one for its next command, the MCP server '
              'needs `native_connect` again. Use one client per device.',
              kind: .warning,
            ),
          ],
        ),
        DocSection(
          id: 'prompts',
          heading: 'Prompts',
          children: [
            p(
              rich(
                'Name the system UI the flow goes through; the agent switches '
                'lanes on its own. Add the `ws://` URI and the device, as for '
                'any run.',
              ),
            ),
            const PromptCards(_prompts),
          ],
        ),
        DocSection(
          id: 'practices',
          heading: 'How the agent should work',
          children: [
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'Look first: `native_get_elements` lists type, text, id, '
                  'bounds and state, plus `foregroundApp`, the app in front. '
                  'A text field’s typed content is its `value`; its `text` '
                  'stays the label.',
                ),
              ),
              li(
                rich(
                  'Select by `text`, `textContains`, `id`, `type` and '
                  '`index`; `native_enter_text` takes the field’s `label`. '
                  'An ambiguous selector fails and lists the candidates, '
                  'instead of guessing.',
                ),
              ),
              li(
                rich(
                  'Native coordinates (`x`/`y`, bounds, swipe points) are '
                  'screen pixels on every platform. Never reuse Flutter '
                  'coordinates in the native lane, or the other way round.',
                ),
              ),
              li(
                rich(
                  '`native_take_screenshot` fits the image in 2000×2000, like '
                  '`take_screenshots`. When it shrinks it, the result gives '
                  'the factor: multiply a point read off the image by it to '
                  'get native `x`/`y`.',
                ),
              ),
              li(
                rich(
                  'Wait with `native_wait_for` (`visible` or `gone`) for a '
                  'dialog or the next screen, not with fixed delays. Wait for '
                  'an element of that screen, not for a package name.',
                ),
              ),
              li(
                rich(
                  'Scroll with `native_scroll`: with a target it stops once '
                  'the target is visible or the list ends; `within` scrolls a '
                  'nested list or a picker wheel. `native_swipe` is a raw '
                  'gesture that does not wait for the content to settle.',
                ),
              ),
              li(
                rich(
                  'Hide the keyboard with `native_hide_keyboard` when it '
                  'covers the next target. `native_enter_text` without a '
                  'selector types into the focused field.',
                ),
              ),
              li(
                rich(
                  'A disabled element is refused, not touched: on iOS the '
                  'app’s elements stay listed, disabled, under a system '
                  'sheet. Act on the sheet first.',
                ),
              ),
              li(
                rich(
                  'Read before you look: `native_get_elements` costs a few '
                  'hundred tokens on a system screen, a screenshot about '
                  '1.5k. `native_take_screenshot` shows the whole screen, '
                  'system UI included, so use it for what the tree does not '
                  'show, such as banners, toasts or a camera preview.',
                ),
              ),
            ]),
          ],
        ),
        DocSection(
          id: 'permissions',
          heading: 'Permission dialogs',
          children: [
            p(
              rich(
                'Answer the dialog the way a user does: `native_wait_for` the '
                'button, then `native_tap` it, for example `text: "Allow"`. '
                'The system shows a dialog only while the permission is '
                'undecided. To see it again, reset the permission outside '
                'Marionette:',
              ),
            ),
            const CodeBlock(
              source: _resetPermission,
              language: .shell,
              title: 'terminal',
            ),
            const Callout(
              'Resetting a permission usually ends the app, and with it the '
              'Flutter connection: run the app again and `connect` again.',
            ),
          ],
        ),
        DocSection(
          id: 'notifications',
          heading: 'Notifications',
          children: [
            p(
              rich(
                '`native_notifications` opens and closes the notification '
                'shade on Android and the Notification Center on iOS. Read '
                'the notifications with `native_get_elements`, open one with '
                '`native_tap`.',
              ),
            ),
            ul(classes: Prose.checklist.name, [
              li(
                rich(
                  'On iOS, send the app to the background first '
                  '(`native_press_key` `home`): opened over the app, the '
                  'Notification Center is not in the tree.',
                ),
              ),
              li(
                rich(
                  'iOS groups an app’s notifications: the first tap on a '
                  'group expands it. A tap on a notification may only slide '
                  'it aside and show "Open"; then wait for it and tap it.',
                ),
              ),
              li(
                rich(
                  'Android heads-up banners, and toasts on recent versions, '
                  'appear only on `native_take_screenshot`.',
                ),
              ),
            ]),
          ],
        ),
        const DocSection(
          id: 'tools',
          heading: 'Every native tool',
          children: [
            DocTable(
              headers: ['MCP tool', 'CLI command', 'What it does'],
              rows: [
                [
                  '`native_connect`',
                  '`native-connect`',
                  'Start the device-side server and a session.',
                ],
                [
                  '`native_disconnect`',
                  '`native-disconnect`',
                  'End the session; stop the server it started.',
                ],
                [
                  '`native_get_elements`',
                  '`native-get-elements`',
                  'List what is on screen, with state.',
                ],
                [
                  '`native_wait_for`',
                  '`native-wait-for`',
                  'Wait until an element is visible or gone.',
                ],
                [
                  '`native_tap`',
                  '`native-tap`',
                  'By selector, or at `x`/`y` in screen pixels.',
                ],
                [
                  '`native_enter_text`',
                  '`native-enter-text`',
                  'Type into a field, or the focused one.',
                ],
                [
                  '`native_scroll`',
                  '`native-scroll`',
                  'In a direction, to a target, or `within` a list.',
                ],
                [
                  '`native_swipe`',
                  '`native-swipe`',
                  'From one point to another: drags, edge gestures.',
                ],
                [
                  '`native_press_key`',
                  '`native-press-key`',
                  '`back` (Android), `home`, `enter` and more.',
                ],
                [
                  '`native_hide_keyboard`',
                  '`native-hide-keyboard`',
                  'Hide the software keyboard.',
                ],
                [
                  '`native_take_screenshot`',
                  '`native-take-screenshot`',
                  'The whole screen; `inline: false` saves it.',
                ],
                [
                  '`native_notifications`',
                  '`native-notifications`',
                  'Open or close the notification list.',
                ],
                [
                  '—',
                  '`native-sessions`',
                  'List the CLI’s device connections.',
                ],
              ],
            ),
          ],
        ),
        DocSection(
          id: 'reports',
          heading: 'In session reports',
          children: [
            p(
              rich(
                'Native calls go into the same `steps.md` as the Flutter '
                'ones, once `connect` has opened a session, so a report '
                'covers both lanes. Text typed with `native_enter_text` is '
                'logged as its length, never as the text. '
                '`native_take_screenshot(inline: false)` saves into '
                '`screenshots/` like `take_screenshots`. See '
                '[Reports](/docs/reports#steps).',
              ),
            ),
            const Callout(
              'A `native-*` CLI command has no Flutter connection to ask '
              'whether reports are on, so it logs its step only when '
              '`--session` or `--session-dir` is given.',
            ),
          ],
        ),
        const DocSection(
          id: 'symptoms',
          heading: 'Start from the symptom',
          children: [
            DocTable(
              headers: ['Symptom', 'Fix'],
              rows: [
                [
                  'A Flutter tap does nothing while a dialog is open',
                  'System UI covers the app: use the native tools.',
                ],
                [
                  '`native_connect` on Android: no device or no adb',
                  'Start an emulator; put platform-tools on `PATH`.',
                ],
                [
                  '`native_connect` on Android: the device is locked',
                  'Unlock it once after a restart, then connect again.',
                ],
                [
                  '`native_connect` on iOS: no WebDriverAgent build',
                  'Build it once: [Set up the device](#setup).',
                ],
                [
                  '`native_connect` on iOS: port 8100 is taken',
                  'Stop what `lsof -nP -iTCP:8100 -sTCP:LISTEN` shows.',
                ],
                [
                  'A native call says several elements match',
                  'Add `index`, or a more specific `type` or `id`.',
                ],
                [
                  'A native call says the session or server is gone',
                  '`native_connect` again; one client per device.',
                ],
                [
                  '`native_wait_for` misses an element you can see',
                  'It is below the screen edge: scroll it into view.',
                ],
                [
                  '`native_hide_keyboard` refuses on an emulator',
                  "Gboard's floating toolbar: unfocus the field in the app.",
                ],
                [
                  'An iOS notification does not open on tap',
                  'Tap it in the expanded group, then tap "Open".',
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }
}
