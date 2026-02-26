import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class ScrollToCommand extends InstanceCommand {
  ScrollToCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('text', help: 'Visible text of the element to scroll to.');
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'scroll-to';

  @override
  String get description =>
      'Scroll until an element matching the criteria is visible.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final matcher = buildMatcherFromArgs(
      key: argResults?['key'] as String?,
      text: argResults?['text'] as String?,
    );

    if (matcher.isEmpty) {
      usageException('At least one matcher required: --key or --text.');
    }

    final response = await connector.scrollToElement(matcher);
    final message =
        response['message'] as String? ?? 'Successfully scrolled to element';
    stdout.writeln(message);
    return 0;
  }
}
