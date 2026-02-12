import 'dart:io';

import 'package:marionette_mcp/marionette_mcp.dart';

import '../../instance_registry.dart';
import '../instance_command.dart';

class HotReloadCommand extends InstanceCommand {
  HotReloadCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'hot-reload';

  @override
  String get description => 'Perform a hot reload of the Flutter app.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final reloaded = await connector.hotReload();

    if (reloaded) {
      stdout.writeln('Hot reload completed successfully.');
      return 0;
    } else {
      stderr.writeln('Hot reload failed. The app may need a full restart.');
      return 1;
    }
  }
}
