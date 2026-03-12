import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class DoubleTapCommand extends InstanceCommand {
  DoubleTapCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('text', help: 'Visible text content of the element.')
      ..addOption('type', help: 'Widget type name (e.g., ListTile).')
      ..addOption('x', help: 'X coordinate for positional double tap.')
      ..addOption('y', help: 'Y coordinate for positional double tap.')
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
      'Double tap an element by key, text, type, or coordinates.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final matcher = buildMatcherFromArgs(
      key: argResults?['key'] as String?,
      text: argResults?['text'] as String?,
      type: argResults?['type'] as String?,
      x: _parseNum(argResults?['x'] as String?),
      y: _parseNum(argResults?['y'] as String?),
    );

    if (matcher.isEmpty) {
      usageException(
        'At least one matcher required: --key, --text, --type, or --x/--y.',
      );
    }

    final delayStr = argResults?['delay'] as String? ?? '100';
    final delay = int.tryParse(delayStr);
    if (delay == null) {
      usageException('--delay must be an integer, got: "$delayStr"');
    }

    final response = await connector.doubleTap(matcher, delayMs: delay);
    final message =
        response['message'] as String? ?? 'Successfully double tapped';
    stdout.writeln(message);
    return 0;
  }

  num? _parseNum(String? value) {
    if (value == null) return null;
    return num.tryParse(value);
  }
}
