import 'package:marionette_flutter/src/binding/extension_schema.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';

/// Callback type for Marionette extension handlers.
typedef MarionetteExtensionCallback = Future<MarionetteExtensionResult>
    Function(Map<String, String> params);

/// Details about a registered custom extension.
class ExtensionDetails {
  /// Creates extension details with the given [name], optional [description],
  /// and optional [inputSchema].
  const ExtensionDetails({
    required this.name,
    this.description,
    this.inputSchema,
  });

  /// The name of the extension (without the `ext.flutter.` prefix).
  final String name;

  /// An optional description of what the extension does.
  final String? description;

  /// An optional typed JSON Schema describing the parameters accepted by the
  /// extension.
  ///
  /// When provided, the MCP server promotes this extension to a first-class
  /// MCP tool with this schema as its input contract — clients get
  /// argument autocomplete and validation. When omitted, the extension is
  /// only reachable via the generic `call_custom_extension` escape hatch.
  ///
  /// Built via [ExtensionInputSchema] / [ExtensionParam]; the underlying
  /// JSON Schema is produced lazily by [ExtensionInputSchema.toJson].
  final ExtensionInputSchema? inputSchema;
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
/// An optional [inputSchema] can be provided as an [ExtensionInputSchema]
/// describing the extension's parameters. When supplied, the MCP server
/// promotes the extension to a first-class MCP tool — clients see it
/// alongside the built-in marionette tools with full argument autocomplete
/// and validation. Without a schema, the extension stays reachable only
/// through the generic `call_custom_extension` tool.
///
/// The schema is restricted at the type level to a flat object with scalar
/// properties (`string`, `integer`, `number`, `boolean`). The Dart VM service
/// serializes parameters as strings, so nested objects/arrays cannot travel
/// as a single param.
///
/// The `ext.flutter.` prefix is added automatically to [name].
///
/// Throws [ArgumentError] if [name] is empty or already contains the
/// `ext.flutter.` prefix.
void registerMarionetteExtension({
  required String name,
  String? description,
  ExtensionInputSchema? inputSchema,
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
    ExtensionDetails(
      name: name,
      description: description,
      inputSchema: inputSchema,
    ),
  );

  registerInternalMarionetteExtension(name: name, callback: callback);
}
