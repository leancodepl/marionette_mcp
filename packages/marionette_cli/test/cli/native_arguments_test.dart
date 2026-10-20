import 'package:marionette_cli/src/cli/commands/native_device_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_gesture_commands.dart';
import 'package:marionette_cli/src/cli/commands/native_inspection_commands.dart';
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
  'native_take_screenshot': {'text', 'textContains', 'id', 'type', 'index'},
  'native_device_info': {},
  'native_tap': {'text', 'textContains', 'id', 'type', 'index', 'x', 'y'},
  'native_double_tap': {
    'text',
    'textContains',
    'id',
    'type',
    'index',
    'x',
    'y',
    'delayMs',
  },
  'native_long_press': {
    'text',
    'textContains',
    'id',
    'type',
    'index',
    'x',
    'y',
    'durationMs',
  },
  'native_pinch': {
    'scale', 'text', 'textContains', 'id', 'type', 'index', 'x', 'y', //
    'durationMs',
  },
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
  'native_permissions': {'action', 'permission', 'appId'},
  'native_open_url': {'url'},
  'native_app': {'action', 'appId'},
  'native_notifications': {'action', 'title', 'body', 'payload', 'appId'},
  'native_set_orientation': {'orientation'},
  'native_set_location': {'latitude', 'longitude'},
  'native_biometrics': {'action'},
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
      ['-o', 'x.png', '--id', 'map', '--index', '1'],
      {'id': 'map', 'index': 1},
    ),
    (NativeDeviceInfoCommand(registry), 'native_device_info', [], {}),
    (
      NativeTapCommand(registry),
      'native_tap',
      ['--x', '10', '--y', '20.5'],
      {'x': 10, 'y': 20.5},
    ),
    (
      NativeDoubleTapCommand(registry),
      'native_double_tap',
      ['--text', 'Here', '--index', '0', '--delay-ms', '80'],
      {'text': 'Here', 'index': 0, 'delayMs': 80},
    ),
    (
      NativeLongPressCommand(registry),
      'native_long_press',
      ['--x', '1', '--y', '2', '--duration-ms', '900'],
      {'x': 1, 'y': 2, 'durationMs': 900},
    ),
    (
      NativePinchCommand(registry),
      'native_pinch',
      ['--scale', '0.5', '--type', 'Map', '--duration-ms', '400'],
      {'scale': 0.5, 'type': 'Map', 'durationMs': 400},
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
      NativePermissionsCommand(registry),
      'native_permissions',
      ['--action', 'reset', '--permission', 'all', '--app-id', 'a.b'],
      {'action': 'reset', 'permission': 'all', 'appId': 'a.b'},
    ),
    (
      NativeOpenUrlCommand(registry),
      'native_open_url',
      ['--url', 'app://x?y=1'],
      {'url': 'app://x?y=1'},
    ),
    (
      NativeAppCommand(registry),
      'native_app',
      ['--action', 'restart', '--app-id', 'a.b'],
      {'action': 'restart', 'appId': 'a.b'},
    ),
    (
      NativeNotificationsCommand(registry),
      'native_notifications',
      [
        '--action',
        'push',
        '--title',
        'T',
        '--body',
        'B',
        '--app-id',
        'a.b',
        '--payload',
        '{"aps": {"alert": "x"}}',
      ],
      {
        'action': 'push',
        'title': 'T',
        'body': 'B',
        'appId': 'a.b',
        'payload': {
          'aps': {'alert': 'x'},
        },
      },
    ),
    (
      NativeSetOrientationCommand(registry),
      'native_set_orientation',
      ['--orientation', 'landscape'],
      {'orientation': 'landscape'},
    ),
    (
      NativeSetLocationCommand(registry),
      'native_set_location',
      ['--latitude', '52.2297', '--longitude', '21.0122'],
      {'latitude': 52.2297, 'longitude': 21.0122},
    ),
    (
      NativeBiometricsCommand(registry),
      'native_biometrics',
      ['--action', 'nonMatch'],
      {'action': 'nonMatch'},
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

    expect(
      mapped,
      {..._toolProperties.keys},
      reason: 'native_map_flutter_rect is covered in native_command_test',
    );
  });
}
