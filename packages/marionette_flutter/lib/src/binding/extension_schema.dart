import 'package:meta/meta.dart';

/// Typed JSON Schema for the input parameters of a custom Marionette
/// extension.
///
/// Equivalent of `ToolInputSchema` from the `mcp_dart` package, restricted to
/// what the Dart VM service can actually carry: a flat object whose
/// properties are scalar types. Nested objects/arrays cannot travel as a
/// single VM service param (params are flattened to strings on the wire), so
/// the type system makes that constraint a compile-time guarantee.
///
/// `toJson()` emits a JSON Schema object compatible with what
/// `marionette_mcp` parses via `mcp_dart`'s `JsonSchema.fromJson` — devs
/// don't have to memorize the JSON Schema field names.
@immutable
class ExtensionInputSchema {
  const ExtensionInputSchema({
    this.properties = const {},
    this.required = const [],
    this.title,
    this.description,
  });

  /// Per-property schemas keyed by parameter name.
  final Map<String, ExtensionParam> properties;

  /// Names of properties that must be present.
  final List<String> required;

  /// Human-readable title for the schema. Optional.
  final String? title;

  /// Human-readable description for the schema. Optional.
  final String? description;

  /// Serializes to a JSON Schema object as expected by the MCP wire format
  /// produced by `marionette.listExtensions`.
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      'type': 'object',
      'properties': {
        for (final entry in properties.entries) entry.key: entry.value.toJson(),
      },
      if (required.isNotEmpty) 'required': List<String>.from(required),
    };
  }
}

/// A typed schema for a single property of an [ExtensionInputSchema].
///
/// Mirrors the scalar factories of `mcp_dart`'s `JsonSchema` (`.string`,
/// `.integer`, `.number`, `.boolean`). Non-scalar factories are deliberately
/// absent — see [ExtensionInputSchema] for why.
@immutable
sealed class ExtensionParam {
  const ExtensionParam({this.title, this.description});

  /// Optional human-readable title for the property.
  final String? title;

  /// Optional human-readable description for the property.
  final String? description;

  /// A string property.
  ///
  /// `enumValues`, when set, restricts the property to that finite list of
  /// strings. Unlike `mcp_dart`'s `JsonString`, the legacy `enumNames` field
  /// is not exposed.
  const factory ExtensionParam.string({
    String? title,
    String? description,
    String? defaultValue,
    int? minLength,
    int? maxLength,
    String? pattern,
    String? format,
    List<String>? enumValues,
  }) = StringParam;

  /// An integer property. All numeric bounds are integers.
  const factory ExtensionParam.integer({
    String? title,
    String? description,
    int? defaultValue,
    int? minimum,
    int? maximum,
    int? exclusiveMinimum,
    int? exclusiveMaximum,
    int? multipleOf,
  }) = IntegerParam;

  /// A number property (any JSON number — int or double).
  const factory ExtensionParam.number({
    String? title,
    String? description,
    num? defaultValue,
    num? minimum,
    num? maximum,
    num? exclusiveMinimum,
    num? exclusiveMaximum,
    num? multipleOf,
  }) = NumberParam;

  /// A boolean property.
  const factory ExtensionParam.boolean({
    String? title,
    String? description,
    bool? defaultValue,
  }) = BooleanParam;

  /// Serializes the property to a JSON Schema fragment.
  Map<String, dynamic> toJson();
}

/// JSON Schema fragment for a string-valued extension parameter.
class StringParam extends ExtensionParam {
  const StringParam({
    super.title,
    super.description,
    this.defaultValue,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.format,
    this.enumValues,
  });

  final String? defaultValue;
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final String? format;
  final List<String>? enumValues;

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'string',
      if (minLength != null) 'minLength': minLength,
      if (maxLength != null) 'maxLength': maxLength,
      if (pattern != null) 'pattern': pattern,
      if (format != null) 'format': format,
      if (enumValues != null) 'enum': List<String>.from(enumValues!),
    };
  }
}

/// JSON Schema fragment for an integer-valued extension parameter.
class IntegerParam extends ExtensionParam {
  const IntegerParam({
    super.title,
    super.description,
    this.defaultValue,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
  });

  final int? defaultValue;
  final int? minimum;
  final int? maximum;
  final int? exclusiveMinimum;
  final int? exclusiveMaximum;
  final int? multipleOf;

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'integer',
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
      if (exclusiveMinimum != null) 'exclusiveMinimum': exclusiveMinimum,
      if (exclusiveMaximum != null) 'exclusiveMaximum': exclusiveMaximum,
      if (multipleOf != null) 'multipleOf': multipleOf,
    };
  }
}

/// JSON Schema fragment for a number-valued (int or double) extension
/// parameter.
class NumberParam extends ExtensionParam {
  const NumberParam({
    super.title,
    super.description,
    this.defaultValue,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
  });

  final num? defaultValue;
  final num? minimum;
  final num? maximum;
  final num? exclusiveMinimum;
  final num? exclusiveMaximum;
  final num? multipleOf;

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'number',
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
      if (exclusiveMinimum != null) 'exclusiveMinimum': exclusiveMinimum,
      if (exclusiveMaximum != null) 'exclusiveMaximum': exclusiveMaximum,
      if (multipleOf != null) 'multipleOf': multipleOf,
    };
  }
}

/// JSON Schema fragment for a boolean-valued extension parameter.
class BooleanParam extends ExtensionParam {
  const BooleanParam({
    super.title,
    super.description,
    this.defaultValue,
  });

  final bool? defaultValue;

  @override
  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      'type': 'boolean',
    };
  }
}
