import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/commands/long_press_command.dart';
import 'package:marionette_cli/src/cli/commands/pinch_zoom_command.dart';
import 'package:marionette_cli/src/cli/commands/swipe_command.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/marionette_command_runner.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

class _FakeConnector implements VmServiceConnector {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _CapturingConnector extends _FakeConnector {
  Map<String, dynamic>? swipeArgs;

  @override
  Future<Map<String, dynamic>> swipe(Map<String, dynamic> args) async {
    swipeArgs = args;
    return const {'message': 'Swiped'};
  }
}

mixin _TestableCommand on InstanceCommand {
  ArgResults? _overriddenArgResults;

  @override
  ArgResults? get argResults => _overriddenArgResults;

  Future<int> executeWithArgs(
    List<String> args,
    VmServiceConnector connector,
  ) async {
    CommandRunner<int>('marionette', '').addCommand(this);
    _overriddenArgResults = argParser.parse(args);
    return execute(connector);
  }
}

class _TestableLongPressCommand extends LongPressCommand with _TestableCommand {
  _TestableLongPressCommand(super.registry);
}

class _TestablePinchZoomCommand extends PinchZoomCommand with _TestableCommand {
  _TestablePinchZoomCommand(super.registry);
}

class _TestableSwipeCommand extends SwipeCommand with _TestableCommand {
  _TestableSwipeCommand(super.registry);
}

void main() {
  group('CLI gesture command validation', () {
    final registry = InstanceRegistry();
    final connector = _FakeConnector();

    test('long-press rejects a non-positive --duration', () async {
      await expectLater(
        _TestableLongPressCommand(registry)
            .executeWithArgs(['--key', 'k', '--duration', '0'], connector),
        throwsA(isA<UsageException>()),
      );
    });

    test('pinch-zoom rejects a non-finite --scale', () async {
      await expectLater(
        _TestablePinchZoomCommand(registry)
            .executeWithArgs(['--key', 'k', '--scale', 'NaN'], connector),
        throwsA(isA<UsageException>()),
      );
    });

    test('pinch-zoom rejects a non-finite --start-distance', () async {
      await expectLater(
        _TestablePinchZoomCommand(registry).executeWithArgs(
          ['--key', 'k', '--scale', '2', '--start-distance', 'Infinity'],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
    });

    test('swipe rejects a --distance of 0', () async {
      await expectLater(
        _TestableSwipeCommand(registry).executeWithArgs(
          ['--key', 'k', '--direction', 'left', '--distance', '0'],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
    });

    test('swipe rejects a non-finite --distance', () async {
      await expectLater(
        _TestableSwipeCommand(registry).executeWithArgs(
          ['--key', 'k', '--direction', 'left', '--distance', 'NaN'],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
    });

    test('swipe rejects a --hold-duration of 0', () async {
      await expectLater(
        _TestableSwipeCommand(registry).executeWithArgs(
          ['--key', 'k', '--direction', 'up', '--hold-duration', '0'],
          connector,
        ),
        throwsA(isA<UsageException>()),
      );
    });

    test('swipe forwards --hold-duration in coordinate mode', () async {
      final capturingConnector = _CapturingConnector();

      await _TestableSwipeCommand(registry).executeWithArgs(
        [
          ...['--start-x', '10', '--start-y', '20'],
          ...['--end-x', '30', '--end-y', '40'],
          ...['--hold-duration', '600'],
        ],
        capturingConnector,
      );

      expect(capturingConnector.swipeArgs, {
        'startX': '10',
        'startY': '20',
        'endX': '30',
        'endY': '40',
        'holdDuration': 600,
      });
    });
  });

  test('a usage error from execute() exits with 64 through the runner',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((data) {
        final rpc = jsonDecode(data as String) as Map<String, dynamic>;
        final result = switch (rpc['method']) {
          'getVM' => {
              'type': 'VM',
              'isolates': [
                {'type': '@Isolate', 'id': 'isolates/1'},
              ],
            },
          'getIsolate' => {
              'type': 'Isolate',
              'id': 'isolates/1',
              'extensionRPCs': ['ext.flutter.marionette.getLogs'],
            },
          _ => {'type': 'Success'},
        };
        socket.add(
          jsonEncode({'jsonrpc': '2.0', 'id': rpc['id'], 'result': result}),
        );
      });
    });

    final exitCode = await MarionetteCommandRunner()
        .run(['--uri', 'ws://127.0.0.1:${server.port}/ws', 'tap']);

    expect(exitCode, equals(64));
  });
}
