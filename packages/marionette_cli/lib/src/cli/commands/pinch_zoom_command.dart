import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class PinchZoomCommand extends InstanceCommand {
  PinchZoomCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('text', help: 'Visible text content of the element.')
      ..addOption('type', help: 'Widget type name (e.g., InteractiveViewer).')
      ..addOption('x', help: 'X coordinate for pinch center.')
      ..addOption('y', help: 'Y coordinate for pinch center.')
      ..addOption(
        'scale',
        help: 'Zoom scale factor. >1.0 zooms in, <1.0 zooms out.',
        mandatory: true,
      )
      ..addOption(
        'start-distance',
        help: 'Initial finger distance in pixels.',
        defaultsTo: '200',
      );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'pinch-zoom';

  @override
  String get description =>
      'Pinch zoom on an element by key, text, type, or coordinates.';

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

    final scaleStr = argResults?['scale'] as String;
    final scale = double.tryParse(scaleStr);
    if (scale == null || scale <= 0) {
      usageException('--scale must be a positive number, got "$scaleStr".');
    }

    final distanceStr = argResults?['start-distance'] as String;
    final startDistance = double.tryParse(distanceStr);
    if (startDistance == null || startDistance <= 0) {
      usageException(
        '--start-distance must be a positive number, got "$distanceStr".',
      );
    }

    final response = await connector.pinchZoom(
      matcher,
      scale: scale,
      startDistance: startDistance,
    );
    final message =
        response['message'] as String? ?? 'Successfully pinch zoomed';
    stdout.writeln(message);
    return 0;
  }

  num? _parseNum(String? value) {
    if (value == null) return null;
    return num.tryParse(value);
  }
}
