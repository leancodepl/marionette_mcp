import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/commands/tap_command.dart';
import 'package:marionette_cli/src/cli/commands/double_tap_command.dart';
import 'package:marionette_cli/src/cli/commands/secondary_tap_command.dart';
import 'package:marionette_cli/src/cli/commands/long_press_command.dart';
import 'package:marionette_cli/src/cli/commands/pinch_zoom_command.dart';
import 'package:marionette_cli/src/cli/commands/enter_text_command.dart';
import 'package:marionette_cli/src/cli/commands/scroll_to_command.dart';
import 'package:marionette_cli/src/cli/commands/swipe_command.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/runtime.dart';
import 'package:test/test.dart';

mixin _ParsedCommand on InstanceCommand {
  ArgResults? parsed;

  @override
  ArgResults? get argResults => parsed;

  Future<int> executeWithArgs(List<String> args, VmServiceConnector connector) {
    CommandRunner<int>('marionette', 'Selector command tests').addCommand(this);
    parsed = argParser.parse(args);
    return execute(connector);
  }
}

class _Connector implements VmServiceConnector {
  final calls = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return Future<Map<String, dynamic>>.value({});
  }
}

class _Tap extends TapCommand with _ParsedCommand {
  _Tap() : super(InstanceRegistry());
}

class _DoubleTap extends DoubleTapCommand with _ParsedCommand {
  _DoubleTap() : super(InstanceRegistry());
}

class _SecondaryTap extends SecondaryTapCommand with _ParsedCommand {
  _SecondaryTap() : super(InstanceRegistry());
}

class _LongPress extends LongPressCommand with _ParsedCommand {
  _LongPress() : super(InstanceRegistry());
}

class _PinchZoom extends PinchZoomCommand with _ParsedCommand {
  _PinchZoom() : super(InstanceRegistry());
}

class _EnterText extends EnterTextCommand with _ParsedCommand {
  _EnterText() : super(InstanceRegistry());
}

class _ScrollTo extends ScrollToCommand with _ParsedCommand {
  _ScrollTo() : super(InstanceRegistry());
}

class _Swipe extends SwipeCommand with _ParsedCommand {
  _Swipe() : super(InstanceRegistry());
}

void main() {
  final gestures = <String, _ParsedCommand Function()>{
    'tap': _Tap.new,
    'double-tap': _DoubleTap.new,
    'secondary-tap': _SecondaryTap.new,
    'long-press': _LongPress.new,
    'pinch-zoom': _PinchZoom.new,
  };
  for (final entry in gestures.entries) {
    group(entry.key, () {
      final requiredArgs =
          entry.key == 'pinch-zoom' ? ['--scale', '2'] : <String>[];
      final invalidArgs = <List<String>>[
        ['--x', '10'],
        ['--y', '20'],
        ['--x', 'typo', '--y', '20'],
        ['--key', 'buy', '--x', 'typo', '--y', '20'],
        ['--x', '10', '--y', 'typo'],
        ['--x', 'NaN', '--y', '20'],
        ['--x', '10', '--y', 'Infinity'],
        ['--x', '-Infinity', '--y', '20'],
        ['--key', 'buy', '--x', '10', '--y', '20'],
        ['--identifier', 'buy', '--x', '10', '--y', '20'],
        ['--text', 'Buy', '--x', '10', '--y', '20'],
        ['--type', 'Button', '--x', '10', '--y', '20'],
        ['--ancestor-keys', 'card'],
      ];
      for (final args in invalidArgs) {
        test('rejects ${args.join(' ')} before calling connector', () async {
          final connector = _Connector();
          await expectLater(
            entry.value().executeWithArgs([
              ...args,
              ...requiredArgs,
            ], connector),
            throwsA(isA<UsageException>()),
          );
          expect(connector.calls, isEmpty);
        });
      }
      test('preserves scoped combined element selectors', () async {
        final connector = _Connector();
        await entry.value().executeWithArgs([
          '--key',
          'buy',
          '--identifier',
          'purchase',
          '--text',
          'Buy',
          '--type',
          'Button',
          '--ancestor-keys',
          'outer',
          '--ancestor-keys',
          'inner',
          ...requiredArgs,
        ], connector);
        expect(connector.calls.single.positionalArguments.first, {
          'key': 'buy',
          'identifier': 'purchase',
          'text': 'Buy',
          'type': 'Button',
          'ancestor_keys': '["outer","inner"]',
        });
      });
      test('preserves finite coordinate targeting and scope', () async {
        final connector = _Connector();
        await entry.value().executeWithArgs([
          '--x',
          '-10.5',
          '--y',
          '2e2',
          '--ancestor-keys',
          'card',
          ...requiredArgs,
        ], connector);
        expect(connector.calls.single.positionalArguments.first, {
          'x': -10.5,
          'y': 200,
          'ancestor_keys': '["card"]',
        });
      });
    });
  }
  for (final option in ['scale', 'start-distance']) {
    for (final value in ['NaN', 'Infinity', '-Infinity']) {
      test('pinch-zoom rejects --$option $value before calling connector',
          () async {
        final connector = _Connector();
        await expectLater(
          _PinchZoom().executeWithArgs([
            '--key',
            'image',
            '--scale',
            '2',
            '--$option',
            value,
          ], connector),
          throwsA(isA<UsageException>()),
        );
        expect(connector.calls, isEmpty);
      });
    }
  }
  test('pinch-zoom preserves positive finite scale and start distance',
      () async {
    final connector = _Connector();
    await _PinchZoom().executeWithArgs([
      '--key',
      'image',
      '--scale',
      '0.5',
      '--start-distance',
      '150.5',
    ], connector);
    expect(connector.calls.single.namedArguments, {
      #scale: 0.5,
      #startDistance: 150.5,
    });
  });
  test('enter-text preserves focused targeting with ancestor scope', () async {
    final connector = _Connector();
    await _EnterText().executeWithArgs([
      '--focused',
      '--ancestor-keys',
      'card',
      '--input',
      'Hello',
    ], connector);
    expect(connector.calls.single.positionalArguments, [
      {'focused': true, 'ancestor_keys': '["card"]'},
      'Hello',
    ]);
  });
  for (final selector in ['key', 'identifier', 'text']) {
    test('enter-text rejects focused plus $selector', () async {
      final connector = _Connector();
      await expectLater(
        _EnterText().executeWithArgs([
          '--focused',
          '--$selector',
          'field',
          '--input',
          'Hello',
        ], connector),
        throwsA(isA<UsageException>()),
      );
      expect(connector.calls, isEmpty);
    });
  }
  test('scroll-to preserves scoped text selector', () async {
    final connector = _Connector();
    await _ScrollTo().executeWithArgs([
      '--text',
      'Buy',
      '--ancestor-keys',
      'card',
    ], connector);
    expect(connector.calls.single.positionalArguments.first, {
      'text': 'Buy',
      'ancestor_keys': '["card"]',
    });
  });
  for (final value in ['typo', 'NaN', 'Infinity', '-Infinity']) {
    test('swipe rejects nonfinite or malformed coordinate $value', () async {
      final connector = _Connector();
      await expectLater(
        _Swipe().executeWithArgs([
          '--start-x',
          value,
          '--start-y',
          '10',
          '--end-x',
          '20',
          '--end-y',
          '30',
        ], connector),
        throwsA(isA<UsageException>()),
      );
      expect(connector.calls, isEmpty);
    });
  }
  for (final args in <List<String>>[
    ['--start-x', '10'],
    ['--start-x', '10', '--start-y', '20', '--end-x', '30'],
    [
      '--key',
      'carousel',
      '--start-x',
      '10',
      '--start-y',
      '20',
      '--end-x',
      '30',
      '--end-y',
      '40',
    ],
    ['--ancestor-keys', 'card', '--direction', 'left'],
  ]) {
    test(
      'swipe rejects incomplete or mixed target ${args.join(' ')}',
      () async {
        final connector = _Connector();
        await expectLater(
          _Swipe().executeWithArgs(args, connector),
          throwsA(isA<UsageException>()),
        );
        expect(connector.calls, isEmpty);
      },
    );
  }
  test('swipe preserves scoped element targeting', () async {
    final connector = _Connector();
    await _Swipe().executeWithArgs([
      '--key',
      'carousel',
      '--ancestor-keys',
      'card',
      '--direction',
      'left',
    ], connector);
    expect(connector.calls.single.positionalArguments.first, {
      'key': 'carousel',
      'ancestor_keys': '["card"]',
      'direction': 'left',
      'distance': '200',
    });
  });
  test('swipe preserves finite coordinate representation', () async {
    final connector = _Connector();
    await _Swipe().executeWithArgs([
      '--start-x',
      '-1.5',
      '--start-y',
      '10',
      '--end-x',
      '20',
      '--end-y',
      '30',
    ], connector);
    expect(connector.calls.single.positionalArguments.first, {
      'startX': '-1.5',
      'startY': '10',
      'endX': '20',
      'endY': '30',
    });
  });
}
