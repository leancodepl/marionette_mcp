import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class PressBackButtonCommand extends InstanceCommand {
  PressBackButtonCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'press-back-button';

  @override
  String get description =>
      'Simulates a system back button press (Android back / iOS swipe-back).';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final response = await connector.pressBackButton();

    final message =
        response['message'] as String? ?? 'Back button pressed';
    stdout.writeln(message);
    return 0;
  }
}
