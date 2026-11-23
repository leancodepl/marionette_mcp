import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_cli/src/json_file_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class RegisterCommand extends Command<int> {
  RegisterCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  String get name => 'register';

  @override
  String get description =>
      'Register a Flutter app instance with a name and VM service URI.';

  @override
  String get invocation => 'marionette register <name> <uri>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      usageException('Expected exactly 2 arguments: <name> <uri>');
    }

    final name = rest[0];
    final uri = rest[1];

    JsonFileRegistry.validateName(name);

    if (!supportedVmServiceUriSchemes.contains(Uri.tryParse(uri)?.scheme)) {
      stderr.writeln(
        'Warning: URI "$uri" has no http(s) or ws(s) scheme. '
        'flutter run prints VM service URIs as http://127.0.0.1:PORT/TOKEN=/.',
      );
    }

    final overwritten = await _registry.register(name, uri);

    if (overwritten) {
      stderr.writeln('Updated existing instance "$name" → $uri');
    } else {
      stdout.writeln('Registered instance "$name" → $uri');
    }

    return 0;
  }
}
