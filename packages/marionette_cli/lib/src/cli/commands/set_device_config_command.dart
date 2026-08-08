import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class SetDeviceConfigCommand extends InstanceCommand {
  SetDeviceConfigCommand(this._registry) {
    argParser
      ..addOption(
        'text-scale',
        help: 'Linear text scale (e.g. 1.0, 1.5, 2.0). Must be > 0.',
      )
      ..addOption(
        'bold-text',
        help: 'System bold-text accessibility setting.',
        allowed: ['true', 'false'],
      )
      ..addOption(
        'platform-brightness',
        help: 'System light/dark appearance.',
        allowed: supportedBrightnessValues.toList(),
      )
      ..addOption(
        'disable-animations',
        help: 'System reduce-motion accessibility setting.',
        allowed: ['true', 'false'],
      )
      ..addFlag(
        'reset',
        help: 'Clear every override and revert to platform defaults. '
            'Applied before the other options in the same call.',
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
      'Override device config (text scale, bold text, brightness, '
      'animations) in the running app.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final reset = argResults?['reset'] as bool? ?? false;
    final rawTextScale = argResults?['text-scale'] as String?;
    final rawBoldText = argResults?['bold-text'] as String?;
    final brightness = argResults?['platform-brightness'] as String?;
    final rawDisableAnimations = argResults?['disable-animations'] as String?;

    if (!reset &&
        rawTextScale == null &&
        rawBoldText == null &&
        brightness == null &&
        rawDisableAnimations == null) {
      usageException(
        'At least one option required: --text-scale, --bold-text, '
        '--platform-brightness, --disable-animations, or --reset.',
      );
    }

    double? textScale;
    if (rawTextScale != null) {
      textScale = double.tryParse(rawTextScale);
      if (textScale == null || textScale <= 0) {
        usageException(
          '--text-scale must be a positive number, got "$rawTextScale".',
        );
      }
    }

    final response = await connector.setDeviceConfig(
      textScale: textScale,
      boldText: rawBoldText == null ? null : rawBoldText == 'true',
      platformBrightness: brightness,
      disableAnimations:
          rawDisableAnimations == null ? null : rawDisableAnimations == 'true',
      reset: reset,
    );

    final message = response['message'] as String? ?? 'Device config updated';
    stdout.writeln(message);
    return 0;
  }
}
