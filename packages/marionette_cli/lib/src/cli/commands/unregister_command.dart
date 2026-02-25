import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_mcp/marionette_mcp.dart';

import '../../instance_registry.dart';

class UnregisterCommand extends Command<int> {
  UnregisterCommand(this._registry) {
    argParser
      ..addFlag(
        'all',
        help: 'Remove all registered instances.',
        negatable: false,
      )
      ..addFlag(
        'stale',
        help: 'Remove only instances that are unreachable.',
        negatable: false,
      );
  }

  final InstanceRegistry _registry;

  @override
  String get name => 'unregister';

  @override
  String get description => 'Remove a registered Flutter app instance.';

  @override
  String get invocation => 'marionette unregister [<name> | --all | --stale]';

  @override
  Future<int> run() async {
    final all = argResults!['all'] as bool;
    final stale = argResults!['stale'] as bool;
    final rest = argResults!.rest;

    // Validate mutually exclusive options.
    final modeCount = (all ? 1 : 0) + (stale ? 1 : 0) + (rest.isNotEmpty ? 1 : 0);
    if (modeCount == 0) {
      usageException('Expected <name>, --all, or --stale.');
    }
    if (modeCount > 1) {
      usageException('<name>, --all, and --stale are mutually exclusive.');
    }

    if (all) {
      return _runAll();
    } else if (stale) {
      return _runStale();
    } else {
      return _runSingle(rest);
    }
  }

  int _runAll() {
    final instances = _registry.listAll();
    if (instances.isEmpty) {
      stdout.writeln('No instances registered.');
      return 0;
    }

    for (final info in instances) {
      _registry.unregister(info.name);
      stdout.writeln('Unregistered instance "${info.name}".');
    }

    stdout.writeln('Removed ${instances.length} instance(s).');
    return 0;
  }

  Future<int> _runStale() async {
    final instances = _registry.listAll();
    if (instances.isEmpty) {
      stdout.writeln('No instances registered.');
      return 0;
    }

    final timeoutSeconds =
        int.parse(globalResults?['timeout'] as String? ?? '5');
    var removed = 0;

    stdout.writeln('Checking ${instances.length} instance(s)...\n');

    for (final info in instances) {
      stdout.write('  ${info.name} (${info.uri}) ... ');
      final connector = VmServiceConnector();

      try {
        await connector.connect(info.uri).timeout(
              Duration(seconds: timeoutSeconds),
            );
        stdout.writeln('OK');
      } catch (_) {
        _registry.unregister(info.name);
        stdout.writeln('STALE - removed');
        removed++;
      } finally {
        try {
          await connector.disconnect();
        } catch (_) {}
      }
    }

    stdout.writeln();
    if (removed == 0) {
      stdout.writeln('All instances are reachable. Nothing to remove.');
    } else {
      stdout.writeln('Removed $removed stale instance(s).');
    }

    return 0;
  }

  int _runSingle(List<String> rest) {
    if (rest.length != 1) {
      usageException('Expected exactly 1 argument: <name>');
    }

    final name = rest[0];
    final removed = _registry.unregister(name);

    if (removed) {
      stdout.writeln('Unregistered instance "$name".');
    } else {
      stderr.writeln('Instance "$name" not found.');
      return 1;
    }

    return 0;
  }
}
