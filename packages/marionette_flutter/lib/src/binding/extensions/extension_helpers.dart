import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';

/// Parses an integer-millisecond parameter into a [Duration].
///
/// Returns the parsed [Duration] (or [defaultValue] if the parameter is
/// absent) in `duration`. On parse failure, returns `error` populated with a
/// ready-to-return [MarionetteExtensionResult.invalidParams]; callers should
/// return that result immediately.
///
/// When [requirePositive] is true, zero and negative values are rejected.
({Duration? duration, MarionetteExtensionResult? error}) parseDurationMs(
  Map<String, String> params,
  String key, {
  required Duration defaultValue,
  bool requirePositive = false,
}) {
  final raw = params[key];
  if (raw == null) {
    return (duration: defaultValue, error: null);
  }
  final ms = int.tryParse(raw);
  if (ms == null || (requirePositive && ms <= 0)) {
    return (
      duration: null,
      error: MarionetteExtensionResult.invalidParams(
        'Parameter "$key" must be '
        '${requirePositive ? 'a positive ' : 'a '}number (milliseconds), '
        'got "$raw"',
      ),
    );
  }
  return (duration: Duration(milliseconds: ms), error: null);
}

/// Parses a positive double parameter.
///
/// Returns the parsed value (or [defaultValue] if the parameter is absent)
/// in `value`. On parse failure or non-positive value, returns `error`
/// populated with a [MarionetteExtensionResult.invalidParams]; callers should
/// return that result immediately.
///
/// Pass a `null` [defaultValue] for an optional parameter — `value` is then
/// `null` exactly when the caller omitted it.
({double? value, MarionetteExtensionResult? error}) parsePositiveDouble(
  Map<String, String> params,
  String key, {
  required double? defaultValue,
}) {
  final raw = params[key];
  if (raw == null) {
    return (value: defaultValue, error: null);
  }
  final parsed = double.tryParse(raw);
  if (parsed == null || parsed <= 0) {
    return (
      value: null,
      error: MarionetteExtensionResult.invalidParams(
        'Parameter "$key" must be a positive number, got "$raw"',
      ),
    );
  }
  return (value: parsed, error: null);
}

/// Parses an optional boolean parameter.
///
/// Params arrive as strings, so `true`/`false` are matched literally. Returns
/// `null` in `value` when the parameter is absent. On any other spelling,
/// returns `error` populated with a
/// [MarionetteExtensionResult.invalidParams]; callers should return that
/// result immediately.
({bool? value, MarionetteExtensionResult? error}) parseOptionalBool(
  Map<String, String> params,
  String key,
) {
  final raw = params[key];
  if (raw == null) {
    return (value: null, error: null);
  }
  return switch (raw) {
    'true' => (value: true, error: null),
    'false' => (value: false, error: null),
    _ => (
        value: null,
        error: MarionetteExtensionResult.invalidParams(
          'Parameter "$key" must be "true" or "false", got "$raw"',
        ),
      ),
  };
}
