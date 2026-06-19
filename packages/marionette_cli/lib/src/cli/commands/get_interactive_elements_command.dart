import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class ElementsCommand extends InstanceCommand {
  ElementsCommand(this._registry) {
    argParser.addFlag(
      'compact',
      help: 'Omit verbose widget properties (style/decoration/color blobs); '
          'show only identifying fields and primitive state flags.',
      defaultsTo: false,
    );
  }

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
    final compact = argResults?['compact'] as bool? ?? false;
    final response = await connector.getInteractiveElements(compact: compact);
    final elements = response['elements'] as List<dynamic>;

    stdout.writeln('Found ${elements.length} interactive element(s):\n');

    for (final element in elements) {
      stdout.writeln(formatElement(element as Map<String, dynamic>));
    }

    return 0;
  }
}
