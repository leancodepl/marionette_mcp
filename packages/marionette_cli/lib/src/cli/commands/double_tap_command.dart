import 'dart:io';

import 'package:marionette_cli/src/cli/ancestor_keys_option.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/runtime.dart';

class DoubleTapCommand extends InstanceCommand {
  DoubleTapCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('identifier', help: 'Semantics identifier of the element.')
      ..addOption('text', help: 'Visible text content of the element.')
      ..addOption('type', help: 'Widget type name (e.g., ListTile).')
      ..addOption('x', help: 'X coordinate for positional double tap.')
      ..addOption('y', help: 'Y coordinate for positional double tap.')
      ..addMultiOption('ancestor-keys', help: ancestorKeysHelp)
      ..addOption(
        'delay',
        help: 'Delay between taps in milliseconds.',
        defaultsTo: '100',
      );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'double-tap';

  @override
  String get description =>
      'Double tap an element by key, identifier, text, type, or coordinates.';

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

    final delayStr = argResults?['delay'] as String? ?? '100';
    final delay = int.tryParse(delayStr);
    if (delay == null) {
      usageException('--delay must be an integer, got: "$delayStr"');
    }
    if (delay <= 0) {
      usageException('--delay must be a positive integer, got: "$delayStr"');
    }

    final response = await connector.doubleTap(matcher, delayMs: delay);
    final message =
        response['message'] as String? ?? 'Successfully double tapped';
    stdout.writeln(message);
    return 0;
  }
}
