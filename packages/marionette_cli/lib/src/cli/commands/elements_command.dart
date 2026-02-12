import 'dart:io';

import 'package:marionette_mcp/marionette_mcp.dart';

import '../../instance_registry.dart';
import '../instance_command.dart';

class ElementsCommand extends InstanceCommand {
  ElementsCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'elements';

  @override
  String get description =>
      'List interactive elements in the Flutter app UI tree.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final response = await connector.getInteractiveElements();
    final elements = response['elements'] as List<dynamic>;

    stdout.writeln('Found ${elements.length} interactive element(s):\n');

    for (final element in elements) {
      stdout.writeln(formatElement(element as Map<String, dynamic>));
    }

    return 0;
  }
}
