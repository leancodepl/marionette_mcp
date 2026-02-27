import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class LogsCommand extends InstanceCommand {
  LogsCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'get-logs';

  @override
  String get description => 'Retrieve application logs from the Flutter app.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final response = await connector.getLogs();
    final logs = response['logs'] as List;
    final count = response['count'] as int;

    if (count == 0) {
      stdout.writeln('No logs collected.');
      return 0;
    }

    stdout.writeln('Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n');
    for (final log in logs) {
      stdout.writeln(log);
    }

    return 0;
  }
}
