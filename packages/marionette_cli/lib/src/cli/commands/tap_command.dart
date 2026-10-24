import 'dart:io';

import 'package:marionette_cli/src/cli/ancestor_keys_option.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/runtime.dart';

class TapCommand extends InstanceCommand {
  TapCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('identifier', help: 'Semantics identifier of the element.')
      ..addOption('text', help: 'Visible text content of the element.')
      ..addOption('type', help: 'Widget type name (e.g., ElevatedButton).')
      ..addOption('x', help: 'X coordinate for positional tap.')
      ..addOption('y', help: 'Y coordinate for positional tap.')
      ..addMultiOption('ancestor-keys', help: ancestorKeysHelp);
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'tap';

  @override
  String get description =>
      'Tap an element by key, identifier, text, type, or coordinates.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final matcher = buildValidatedMatcherFromArgs(
      argResults,
      fail: usageException,
    );

    if (!hasSelector(matcher)) {
      usageException(
        'At least one matcher required: --key, --identifier, --text, --type, '
        'or --x/--y.',
      );
    }

    final response = await connector.tap(matcher);
    final message = response['message'] as String? ?? 'Successfully tapped';
    stdout.writeln(message);
    return 0;
  }
}
