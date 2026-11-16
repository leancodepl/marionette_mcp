import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/commands/double_tap_command.dart';
import 'package:marionette_cli/src/cli/commands/long_press_command.dart';
import 'package:marionette_cli/src/cli/commands/pinch_zoom_command.dart';
import 'package:marionette_cli/src/cli/commands/secondary_tap_command.dart';
import 'package:marionette_cli/src/cli/commands/swipe_command.dart';
import 'package:marionette_cli/src/cli/commands/tap_command.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

class _FakeConnector implements VmServiceConnector {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

mixin _TestableCommand on InstanceCommand {
  ArgResults? _overriddenArgResults;

  @override
  ArgResults? get argResults => _overriddenArgResults;

  Future<int> executeWithArgs(
    List<String> args,
    VmServiceConnector connector,
  ) async {
    if (runner == null) {
      CommandRunner<int>('marionette', '').addCommand(this);
    }
    _overriddenArgResults = argParser.parse(args);
    return execute(connector);
  }
}

class _TestableTapCommand extends TapCommand with _TestableCommand {
  _TestableTapCommand(super.registry);
}

class _TestableSecondaryTapCommand extends SecondaryTapCommand
    with _TestableCommand {
  _TestableSecondaryTapCommand(super.registry);
}

class _TestableLongPressCommand extends LongPressCommand with _TestableCommand {
  _TestableLongPressCommand(super.registry);
}

class _TestableDoubleTapCommand extends DoubleTapCommand with _TestableCommand {
  _TestableDoubleTapCommand(super.registry);
}

class _TestablePinchZoomCommand extends PinchZoomCommand with _TestableCommand {
  _TestablePinchZoomCommand(super.registry);
}

class _TestableSwipeCommand extends SwipeCommand with _TestableCommand {
  _TestableSwipeCommand(super.registry);
}

void main() {
  group('CLI gesture command validation', () {
    late InstanceRegistry registry;
    late _FakeConnector connector;

    setUp(() {
      registry = InstanceRegistry();
      connector = _FakeConnector();
    });

    test('tap rejects unpaired --x or --y and non-finite coordinates',
        () async {
      final cmd = _TestableTapCommand(registry);
      await expectLater(
        cmd.executeWithArgs(['--x', '100'], connector),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        cmd.executeWithArgs(['--x', 'NaN', '--y', '100'], connector),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        cmd.executeWithArgs(['--x', 'abc', '--y', '100'], connector),
        throwsA(isA<UsageException>()),
      );
    });

    test('secondary-tap rejects unpaired --x or --y', () async {
      final cmd = _TestableSecondaryTapCommand(registry);
      await expectLater(
        cmd.executeWithArgs(['--y', '50'], connector),
        throwsA(isA<UsageException>()),
      );
    });

    test('long-press rejects unpaired --x/--y and non-positive --duration',
        () async {
      final cmd = _TestableLongPressCommand(registry);
      await expectLater(
        cmd.executeWithArgs(['--x', '50'], connector),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        cmd.executeWithArgs(['--key', 'k', '--duration', '0'], connector),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        cmd.executeWithArgs(['--key', 'k', '--duration', '-10'], connector),
        throwsA(isA<UsageException>()),
      );
    });

    test('double-tap rejects non-finite --x/--y', () async {
      final cmd = _TestableDoubleTapCommand(registry);
      await expectLater(
        cmd.executeWithArgs(['--x', 'Infinity', '--y', '10'], connector),
        throwsA(isA<UsageException>()),
      );
    });

    test('pinch-zoom rejects non-finite --scale and --start-distance',
        () async {
      final cmd = _TestablePinchZoomCommand(registry);
      await expectLater(
        cmd.executeWithArgs(['--key', 'k', '--scale', 'NaN'], connector),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        cmd.executeWithArgs(
          ['--key', 'k', '--scale', '2', '--start-distance', 'Infinity'],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
    });

    test('swipe rejects non-positive or non-finite --distance and coords',
        () async {
      final cmd = _TestableSwipeCommand(registry);
      await expectLater(
        cmd.executeWithArgs(
          ['--key', 'k', '--direction', 'left', '--distance', '0'],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        cmd.executeWithArgs(
          ['--key', 'k', '--direction', 'left', '--distance', 'NaN'],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
      await expectLater(
        cmd.executeWithArgs(
          [
            '--start-x',
            'Infinity',
            '--start-y',
            '0',
            '--end-x',
            '100',
            '--end-y',
            '0',
          ],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
