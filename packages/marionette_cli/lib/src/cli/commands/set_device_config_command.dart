import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class SetDeviceConfigCommand extends InstanceCommand {
  SetDeviceConfigCommand(this._registry) {
    argParser
      ..addOption(
        'text-scale-factor',
        help: 'Text scale factor (e.g., 1.0, 1.5, 2.0). Must be > 0.',
      )
      ..addOption(
        'bold-text',
        help: 'Enable bold text accessibility (true/false).',
        allowed: ['true', 'false'],
      )
      ..addFlag(
        'reset',
        help: 'Reset all overrides to platform defaults.',
        negatable: false,
      );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'set-device-config';

  @override
  String get description =>
      'Override device config (text scale, bold text) for accessibility testing.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final reset = argResults?['reset'] as bool? ?? false;
    final rawTextScale = argResults?['text-scale-factor'] as String?;
    final rawBoldText = argResults?['bold-text'] as String?;

    if (!reset && rawTextScale == null && rawBoldText == null) {
      usageException(
        'At least one option required: '
        '--text-scale-factor, --bold-text, or --reset.',
      );
    }

    double? textScaleFactor;
    if (rawTextScale != null) {
      textScaleFactor = double.tryParse(rawTextScale);
      if (textScaleFactor == null || textScaleFactor <= 0) {
        usageException(
          '--text-scale-factor must be a positive number, got "$rawTextScale".',
        );
      }
    }

    bool? boldText;
    if (rawBoldText != null) {
      boldText = rawBoldText == 'true';
    }

    final response = await connector.setDeviceConfig(
      textScaleFactor: textScaleFactor,
      boldText: boldText,
      reset: reset,
    );

    final message = response['message'] as String? ?? 'Device config updated';
    stdout.writeln(message);
    return 0;
  }
}
