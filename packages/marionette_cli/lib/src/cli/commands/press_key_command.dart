import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class PressKeyCommand extends InstanceCommand {
  PressKeyCommand(this._registry) {
    argParser
      ..addOption(
        'key',
        help: 'Key to press: a named key (enter, tab, escape, backspace, '
            'delete, space, arrowUp/arrowDown/arrowLeft/arrowRight, home, end, '
            'pageUp, pageDown) or a single character a-z / 0-9.',
        mandatory: true,
      )
      ..addOption(
        'modifiers',
        help: 'Comma-separated modifiers to hold: control, shift, alt, meta '
            '(e.g. "control" or "control,shift"). On macOS use meta for Command.',
      );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'press-key';

  @override
  String get description =>
      'Press a keyboard key on the focused element. Produces a real key event '
      '(unlike enter-text): submit with enter, move focus with tab, dismiss '
      'with escape, edit with backspace/arrows, or trigger shortcuts with '
      'modifiers (e.g. --key a --modifiers control).';

  @override
  Future<int> run() {
    // Validate before InstanceCommand.run() connects, so a bad modifier is a
    // usage error (exit 64) that doesn't require a running app.
    final modifierError =
        invalidModifiersError(argResults?['modifiers'] as String?);
    if (modifierError != null) {
      usageException(modifierError);
    }
    return super.run();
  }

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final key = argResults!['key'] as String;
    final modifiers = argResults?['modifiers'] as String?;

    final response = await connector.pressKey(key, modifiers: modifiers);
    final message =
        response['message'] as String? ?? 'Successfully pressed key';
    stdout.writeln(message);
    return 0;
  }
}
