import 'dart:io';

import 'package:args/command_runner.dart';

import '../../instance_registry.dart';

class UnregisterCommand extends Command<int> {
  UnregisterCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  String get name => 'unregister';

  @override
  String get description => 'Remove a registered Flutter app instance.';

  @override
  String get invocation => 'marionette unregister <name>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
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
