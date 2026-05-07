import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';

/// Callback type for Marionette extension handlers.
typedef MarionetteExtensionCallback = Future<MarionetteExtensionResult>
    Function(Map<String, String> params);

/// JSON Schema scalar types accepted in [ExtensionDetails.inputSchema]
/// property definitions.
///
/// The Dart VM service flattens all parameter values to strings on the wire,
/// so callbacks always receive `Map<String, String>` regardless of the
/// declared schema type. Restricting properties to scalars makes that
/// constraint explicit at registration time rather than surprising callers
/// at call time.
const _allowedScalarPropertyTypes = {
  'string',
  'integer',
  'number',
  'boolean',
};

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

  /// An optional JSON Schema describing the parameters accepted by the
  /// extension.
  ///
  /// When provided, the MCP server promotes this extension to a first-class
  /// MCP tool with this schema as its input contract — clients get
  /// argument autocomplete and validation. When omitted, the extension is
  /// only reachable via the generic `call_custom_extension` escape hatch.
  ///
  /// Must be a JSON Schema object (`{"type": "object", ...}`); see
  /// [registerMarionetteExtension] for the validation rules.
  final Map<String, dynamic>? inputSchema;
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
/// An optional [inputSchema] can be provided as a JSON Schema describing the
/// extension's parameters. When supplied, the MCP server promotes the
/// extension to a first-class MCP tool — clients see it alongside the
/// built-in marionette tools with full argument autocomplete and validation.
/// Without a schema, the extension stays reachable only through the generic
/// `call_custom_extension` tool.
///
/// The [inputSchema], if provided, must:
/// - have `"type": "object"` at the top level (MCP requires this);
/// - declare each property's `type` as one of `string`, `integer`, `number`,
///   or `boolean`. The Dart VM service serializes parameters as strings, so
///   nested objects/arrays cannot travel as a single param — split them into
///   multiple scalars or accept a JSON-encoded string.
///
/// The `ext.flutter.` prefix is added automatically to [name].
///
/// Throws [ArgumentError] if [name] is empty, already contains the
/// `ext.flutter.` prefix, or if [inputSchema] violates the rules above.
void registerMarionetteExtension({
  required String name,
  String? description,
  Map<String, dynamic>? inputSchema,
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
  if (inputSchema != null) {
    _validateInputSchema(inputSchema);
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

void _validateInputSchema(Map<String, dynamic> inputSchema) {
  final type = inputSchema['type'];
  if (type != 'object') {
    throw ArgumentError.value(
      inputSchema,
      'inputSchema',
      'top-level "type" must be "object" (got ${type == null ? 'null' : '"$type"'})',
    );
  }

  final properties = inputSchema['properties'];
  if (properties != null && properties is! Map<String, dynamic>) {
    throw ArgumentError.value(
      inputSchema,
      'inputSchema',
      '"properties" must be a JSON object',
    );
  }

  if (properties is Map<String, dynamic>) {
    for (final entry in properties.entries) {
      final propDef = entry.value;
      if (propDef is! Map<String, dynamic>) {
        throw ArgumentError.value(
          inputSchema,
          'inputSchema',
          'property "${entry.key}" must be a JSON Schema object',
        );
      }
      final propType = propDef['type'];
      if (propType is! String ||
          !_allowedScalarPropertyTypes.contains(propType)) {
        throw ArgumentError.value(
          inputSchema,
          'inputSchema',
          'property "${entry.key}" must declare a scalar "type" '
              '(one of ${_allowedScalarPropertyTypes.join(", ")}); '
              'got ${propType == null ? 'null' : '"$propType"'}. '
              'The Dart VM service flattens parameter values to strings, '
              'so nested objects/arrays cannot be represented in the schema.',
        );
      }
    }
  }
}
