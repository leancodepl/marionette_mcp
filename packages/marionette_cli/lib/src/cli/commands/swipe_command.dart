import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/cli/matcher_builder.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class SwipeCommand extends InstanceCommand {
  SwipeCommand(this._registry) {
    argParser
      ..addOption('key', help: 'Element key (ValueKey<String>).')
      ..addOption('identifier', help: 'Semantics identifier of the element.')
      ..addOption('text', help: 'Visible text content of the element.')
      ..addOption('type', help: 'Widget type name (e.g., PageView).')
      ..addOption(
        'direction',
        help: 'Swipe direction for element-based mode: left, right, up, down.',
        allowed: ['left', 'right', 'up', 'down'],
      )
      ..addOption(
        'distance',
        help: 'Swipe distance in pixels for element-based mode.',
        defaultsTo: '200',
      )
      ..addOption('start-x',
          help: 'Start X coordinate for coordinate-based swipe.')
      ..addOption('start-y',
          help: 'Start Y coordinate for coordinate-based swipe.')
      ..addOption('end-x', help: 'End X coordinate for coordinate-based swipe.')
      ..addOption('end-y',
          help: 'End Y coordinate for coordinate-based swipe.');
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'swipe';

  @override
  String get description =>
      'Swipe/drag on an element (key, identifier, text, or type) in a '
      'direction, or between coordinates. Useful for PageView, Dismissible, '
      'Drawer, and Slider widgets.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final startX = argResults?['start-x'] as String?;
    final startY = argResults?['start-y'] as String?;
    final endX = argResults?['end-x'] as String?;
    final endY = argResults?['end-y'] as String?;

    final anyCoordinate =
        startX != null || startY != null || endX != null || endY != null;

    final anyElement = argResults?['key'] != null ||
        argResults?['identifier'] != null ||
        argResults?['text'] != null ||
        argResults?['type'] != null ||
        argResults?['direction'] != null ||
        (argResults?.wasParsed('distance') ?? false);

    if (anyCoordinate && anyElement) {
      usageException(
        'Cannot mix coordinate-based options '
        '(--start-x/--start-y/--end-x/--end-y) with element-based options '
        '(--key/--identifier/--text/--type/--direction/--distance). '
        'Use one mode.',
      );
    }

    final swipeArgs = <String, dynamic>{};

    if (anyCoordinate) {
      if (startX == null || startY == null || endX == null || endY == null) {
        usageException(
          'Coordinate-based swipe requires all of: '
          '--start-x, --start-y, --end-x, --end-y.',
        );
      }
      _ensureNumber('--start-x', startX);
      _ensureNumber('--start-y', startY);
      _ensureNumber('--end-x', endX);
      _ensureNumber('--end-y', endY);
      swipeArgs['startX'] = startX;
      swipeArgs['startY'] = startY;
      swipeArgs['endX'] = endX;
      swipeArgs['endY'] = endY;
    } else {
      final matcher = buildMatcherFromArgs(
        key: argResults?['key'] as String?,
        identifier: argResults?['identifier'] as String?,
        text: argResults?['text'] as String?,
        type: argResults?['type'] as String?,
      );
      if (matcher.isEmpty) {
        usageException(
          'Element-based swipe requires a matcher: --key, --identifier, '
          '--text, or --type. Alternatively provide '
          '--start-x/--start-y/--end-x/--end-y for coordinate-based swipe.',
        );
      }

      final direction = argResults?['direction'] as String?;
      if (direction == null) {
        usageException(
          'Element-based swipe requires --direction '
          '(left, right, up, or down).',
        );
      }

      final distance = argResults?['distance'] as String;
      _ensureNumber('--distance', distance);

      swipeArgs
        ..addAll(matcher)
        ..['direction'] = direction
        ..['distance'] = distance;
    }

    final response = await connector.swipe(swipeArgs);
    final message = response['message'] as String? ?? 'Successfully swiped';
    stdout.writeln(message);
    return 0;
  }

  void _ensureNumber(String flag, String value) {
    if (double.tryParse(value) == null) {
      usageException('$flag must be a number, got "$value".');
    }
  }
}
