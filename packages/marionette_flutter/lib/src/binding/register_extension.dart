import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';

/// Callback type for Marionette extension handlers.
typedef MarionetteExtensionCallback = Future<MarionetteExtensionResult>
    Function(Map<String, String> params);

final List<Map<String, String>> _customExtensionRegistry = [];

/// Unmodifiable view of custom (non-built-in) extensions with their metadata.
///
/// Only extensions registered via [registerMarionetteExtension] are tracked
/// here. Internal extensions registered by [MarionetteBinding] are excluded.
List<Map<String, String>> get customExtensionRegistry =>
    List.unmodifiable(_customExtensionRegistry);

/// Registers a custom app-specific service extension.
///
/// Use this to register extensions that follow the same conventions as the
/// built-in Marionette extensions. The [callback] returns a
/// [MarionetteExtensionResult] which is pattern-matched to produce the
/// appropriate [ServiceExtensionResponse].
///
/// An optional [description] can be provided to describe what the extension
/// does. This description is returned by the `list_custom_extensions` MCP tool
/// so that MCP clients can discover available custom extensions.
///
/// The `ext.flutter.` prefix is added automatically to [name].
void registerMarionetteExtension({
  required String name,
  String? description,
  required MarionetteExtensionCallback callback,
}) {
  _customExtensionRegistry.add({
    'name': name,
    if (description != null) 'description': description,
  });

  registerInternalMarionetteExtension(name: name, callback: callback);
}
