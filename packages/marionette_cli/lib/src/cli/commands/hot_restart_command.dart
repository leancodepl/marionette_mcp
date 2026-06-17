import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class HotRestartCommand extends InstanceCommand {
  HotRestartCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'hot-restart';

  @override
  String get description =>
      'Perform a hot restart of the Flutter app (resets state).';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final restarted = await connector.hotRestart();

    if (restarted) {
      stdout.writeln('Hot restart completed successfully.');
      return 0;
    } else {
      stderr.writeln(
        'Hot restart failed or is unavailable. '
        'Make sure the app is running via `flutter run`.',
      );
      return 1;
    }
  }
}
