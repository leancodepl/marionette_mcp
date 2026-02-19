import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';

/// Callback type for Marionette extension handlers.
typedef MarionetteExtensionCallback = Future<MarionetteExtensionResult>
    Function(Map<String, String> params);

/// Details about a registered custom extension.
class ExtensionDetails {
  /// Creates extension details with the given [name] and optional [description].
  const ExtensionDetails({required this.name, this.description});

  /// The name of the extension (without the `ext.flutter.` prefix).
  final String name;

  /// An optional description of what the extension does.
  final String? description;
}

final List<ExtensionDetails> _customExtensionRegistry = [];

/// Unmodifiable view of custom (non-built-in) extensions with their metadata.
///
/// Only extensions registered via [registerMarionetteExtension] are tracked
/// here. Internal extensions registered by [MarionetteBinding] are excluded.
List<ExtensionDetails> get customExtensionRegistry =>
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
///
/// Throws [ArgumentError] if [name] is empty or already contains the
/// `ext.flutter.` prefix.
void registerMarionetteExtension({
  required String name,
  String? description,
  required MarionetteExtensionCallback callback,
}) {
  if (name.isEmpty) {
    throw ArgumentError.value(name, 'name', 'must not be empty');
  }
  if (name.startsWith('ext.flutter.')) {
    throw ArgumentError.value(
      name,
      'name',
      'must not include the "ext.flutter." prefix, it is added automatically',
    );
  }

  _customExtensionRegistry.add(
    ExtensionDetails(name: name, description: description),
  );

  registerInternalMarionetteExtension(name: name, callback: callback);
}
