import 'package:marionette_cli/src/cli/commands/native_gesture_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_inspection_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_notification_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_text_commands.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:test/test.dart';

/// Argument names of the MCP tools (`tools/list` of the MCP server), which
/// the CLI arguments must be a subset of.
const _toolProperties = <String, Set<String>>{
  'native_get_elements': {
    'text', 'textContains', 'id', 'type', 'clickableOnly', //
    'includeForegroundApp',
  },
  'native_wait_for': {
    'text',
    'textContains',
    'id',
    'type',
    'state',
    'timeoutMs',
    'intervalMs',
  },
  'native_take_screenshot': {},
  'native_tap': {'text', 'textContains', 'id', 'type', 'index', 'x', 'y'},
  'native_swipe': {'startX', 'startY', 'endX', 'endY', 'durationMs'},
  'native_scroll': {
    'direction', 'text', 'textContains', 'id', 'type', 'within', //
    'maxSwipes', 'distance', 'startX', 'startY',
  },
  'native_enter_text': {
    'text',
    'label',
    'textContains',
    'id',
    'type',
    'index',
    'clear',
  },
  'native_press_key': {'key'},
  'native_hide_keyboard': {},
  'native_notifications': {'action'},
};

void main() {
  final registry = NativeSessionRegistry(baseDir: '/nonexistent');

  /// Every option given → the exact tool arguments, with tool types.
  final cases = <(NativeCommand, String, List<String>, Map<String, Object>)>[
    (
      NativeGetElementsCommand(registry),
      'native_get_elements',
      [
        '--text', 'A', '--text-contains', 'B', '--id', 'C', '--type', 'D', //
        '--clickable-only', '--no-include-foreground-app',
      ],
      {
        'text': 'A', 'textContains': 'B', 'id': 'C', 'type': 'D', //
        'clickableOnly': true, 'includeForegroundApp': false,
      },
    ),
    (
      NativeWaitForCommand(registry),
      'native_wait_for',
      [
        '--text-contains',
        'Allow',
        '--state',
        'gone',
        '--timeout-ms',
        '5000',
        '--interval-ms',
        '200',
      ],
      {
        'textContains': 'Allow', 'state': 'gone', 'timeoutMs': 5000, //
        'intervalMs': 200,
      },
    ),
    (
      NativeTakeScreenshotCommand(registry),
      'native_take_screenshot',
      ['-o', 'x.png'],
      {},
    ),
    (
      NativeTapCommand(registry),
      'native_tap',
      ['--x', '10', '--y', '20.5'],
      {'x': 10, 'y': 20.5},
    ),
    (
      NativeSwipeCommand(registry),
      'native_swipe',
      [
        '--start-x', '1', '--start-y', '2', '--end-x', '3', '--end-y', '4', //
        '--duration-ms', '300',
      ],
      {'startX': 1, 'startY': 2, 'endX': 3, 'endY': 4, 'durationMs': 300},
    ),
    (
      NativeScrollCommand(registry),
      'native_scroll',
      [
        '--direction',
        'up',
        '--text',
        'Row 40',
        '--within-id',
        'list',
        '--within-index',
        '0',
        '--max-swipes',
        '5',
        '--distance',
        '300.5',
        '--start-x',
        '100',
        '--start-y',
        '900',
      ],
      {
        'direction': 'up',
        'text': 'Row 40',
        'within': {'id': 'list', 'index': 0},
        'maxSwipes': 5,
        'distance': 300.5,
        'startX': 100,
        'startY': 900,
      },
    ),
    (
      NativeEnterTextCommand(registry),
      'native_enter_text',
      ['--text', 'Gęś', '--label', 'Title', '--clear'],
      {'text': 'Gęś', 'label': 'Title', 'clear': true},
    ),
    (
      NativePressKeyCommand(registry),
      'native_press_key',
      ['--key', 'volume_up'],
      {'key': 'volume_up'},
    ),
    (NativeHideKeyboardCommand(registry), 'native_hide_keyboard', [], {}),
    (
      NativeNotificationsCommand(registry),
      'native_notifications',
      ['--action', 'close'],
      {'action': 'close'},
    ),
  ];

  for (final (command, tool, args, expected) in cases) {
    test('${command.name} → $tool', () {
      final actual = command.argumentsFor(command.argParser.parse(args));

      expect(actual, expected);
      expect(
        _toolProperties[tool],
        containsAll(actual.keys),
        reason: 'only arguments the MCP tool declares',
      );
      // An integer stays an int, a fraction a double — the tools read num.
      for (final MapEntry(:key, :value) in expected.entries) {
        if (value is num) {
          expect(actual[key].runtimeType, value.runtimeType, reason: key);
        }
      }
    });
  }

  test('the enter-text field selector is "label", not "text"', () {
    final command = NativeEnterTextCommand(registry);

    expect(
      command
          .argumentsFor(command.argParser.parse(['--text', 'x', '--id', 'f'])),
      {'text': 'x', 'id': 'f'},
    );
  });

  test('options that are not given are left out (the tool defaults apply)', () {
    final command = NativeGetElementsCommand(registry);

    expect(command.argumentsFor(command.argParser.parse([])), isEmpty);
  });

  test('every MCP tool except connect / disconnect has a command', () {
    final mapped = {for (final (_, tool, _, _) in cases) tool};

    expect(mapped, {..._toolProperties.keys});
  });
}
