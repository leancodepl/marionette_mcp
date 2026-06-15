import 'dart:convert';

/// Coerces JSON arguments into the `Map<String, String>` shape that the Dart
/// VM service expects for custom extension calls.
///
/// Custom extension params travel over the VM service as a flat
/// `Map<String, String>` — the `dart:developer` handler signature is
/// `(String method, Map<String, String> parameters)`, and the VM
/// force-stringifies every value before delivering it. We do the
/// stringification here so the wire payload is well-formed regardless of how
/// the value arrives:
///
/// `int 42 → "42"`, `bool true → "true"`, `null → ""`, lists/maps →
/// `jsonEncode(value)` so callbacks that opt into nested structures receive
/// valid JSON (not Dart's `toString()` form, e.g. `{x: 1}`, which is
/// un-parseable). The Flutter callback is responsible for parsing scalars
/// back into the right Dart type.
///
/// Both the dynamically-promoted extension tools and the generic
/// `call_custom_extension` escape hatch route through this so they produce
/// identical wire args for the same input.
Map<String, dynamic> coerceToStringMap(Map<String, dynamic> args) {
  final result = <String, dynamic>{};
  for (final entry in args.entries) {
    final value = entry.value;
    if (value == null) {
      result[entry.key] = '';
    } else if (value is String) {
      result[entry.key] = value;
    } else if (value is num || value is bool) {
      result[entry.key] = value.toString();
    } else {
      result[entry.key] = jsonEncode(value);
    }
  }
  return result;
}
