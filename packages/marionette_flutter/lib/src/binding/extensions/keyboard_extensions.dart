import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/keyboard_simulator.dart';

/// Registers keyboard `marionette.*` extensions: pressKey.
void registerKeyboardExtensions({
  required KeyboardSimulator keyboardSimulator,
}) {
  registerInternalMarionetteExtension(
    name: 'marionette.pressKey',
    callback: (params) async {
      final key = params['key'];
      if (key == null || key.isEmpty) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: key',
        );
      }

      final modifiers = _parseModifiers(params['modifiers']);

      // KeyboardSimulator throws ArgumentError for an unknown key or modifier,
      // which register_extension_internal maps to an invalidParams response.
      await keyboardSimulator.pressKey(key, modifiers: modifiers);

      final description =
          modifiers.isEmpty ? key : '${modifiers.join('+')}+$key';
      return MarionetteExtensionResult.success({
        'message': 'Pressed key: $description',
      });
    },
  );
}

/// Parses the comma-separated `modifiers` parameter into a set of lower-case
/// modifier names, ignoring blank entries.
Set<String> _parseModifiers(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const {};
  }
  return raw
      .split(',')
      .map((modifier) => modifier.trim().toLowerCase())
      .where((modifier) => modifier.isNotEmpty)
      .toSet();
}
