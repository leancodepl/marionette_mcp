import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class LongPressCommand extends InstanceCommand {
  LongPressCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('text', help: 'Visible text content of the element.')
      ..addOption('type', help: 'Widget type name (e.g., ListTile).')
      ..addOption('x', help: 'X coordinate for positional long press.')
      ..addOption('y', help: 'Y coordinate for positional long press.')
      ..addOption(
        'duration',
        help: 'Hold duration in milliseconds.',
        defaultsTo: '600',
      );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'long-press';

  @override
  String get description =>
      'Long press an element by key, text, type, or coordinates.';

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

    final durationStr = argResults?['duration'] as String? ?? '600';
    final duration = int.tryParse(durationStr);
    if (duration == null) {
      usageException('--duration must be an integer, got: "$durationStr"');
    }

    final response = await connector.longPress(matcher, durationMs: duration);
    final message =
        response['message'] as String? ?? 'Successfully long pressed';
    stdout.writeln(message);
    return 0;
  }

  num? _parseNum(String? value) {
    if (value == null) return null;
    return num.tryParse(value);
  }
}
