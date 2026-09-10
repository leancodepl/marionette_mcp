import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

String formatInteractiveElementsCommandOutput(Map<String, dynamic> response) =>
    formatInteractiveElementsResponse(response);

class ElementsCommand extends InstanceCommand {
  ElementsCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'get-interactive-elements';

  @override
  String get description =>
      'List interactive elements in the Flutter app UI tree.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final response = await connector.getInteractiveElements();
    stdout.write(formatInteractiveElementsCommandOutput(response));

    return 0;
  }
}
