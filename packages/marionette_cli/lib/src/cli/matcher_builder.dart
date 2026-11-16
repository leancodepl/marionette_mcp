import 'dart:convert';

/// Builds a widget matcher map from CLI arguments.
///
/// Accepts named args like --key, --identifier, --text, --type, --x, --y,
/// --ancestor-keys and constructs the matcher map expected by
/// [VmServiceConnector].
Map<String, dynamic> buildMatcherFromArgs({
  String? key,
  String? identifier,
  String? text,
  String? type,
  num? x,
  num? y,
  bool focused = false,
  List<String> ancestorKeys = const [],
}) {
  final matcher = <String, dynamic>{};
  if (key != null) matcher['key'] = key;
  if (identifier != null) matcher['identifier'] = identifier;
  if (text != null) matcher['text'] = text;
  if (type != null) matcher['type'] = type;
  if (x != null) matcher['x'] = x;
  if (y != null) matcher['y'] = y;
  if (focused) matcher['focused'] = true;
  // The VM service only carries string values, so the scope chain travels
  // JSON-encoded — a delimiter could appear inside a key.
  if (ancestorKeys.isNotEmpty) {
    matcher['ancestor_keys'] = jsonEncode(ancestorKeys);
  }
  return matcher;
}

/// Whether [matcher] identifies an element to act on.
///
/// `ancestor_keys` only narrows where the search happens, so a matcher
/// carrying nothing but a scope still selects nothing.
bool hasSelector(Map<String, dynamic> matcher) {
  return matcher.keys.any((field) => field != 'ancestor_keys');
}

/// Parses a finite coordinate value from a CLI flag, invoking [onUsageError]
/// when [value] is non-null and not a finite number.
num? parseCoordinate(
  String flag,
  String? value,
  Never Function(String message) onUsageError,
) {
  if (value == null) return null;
  final parsed = num.tryParse(value);
  if (parsed == null || !parsed.isFinite) {
    onUsageError('$flag must be a finite number, got "$value".');
  }
  return parsed;
}

/// Validates and builds a matcher map for commands that support `--x`/`--y`
/// positional selectors alongside widget selectors.
Map<String, dynamic> buildValidatedMatcherFromArgs({
  String? key,
  String? identifier,
  String? text,
  String? type,
  String? x,
  String? y,
  List<String> ancestorKeys = const [],
  required Never Function(String message) onUsageError,
}) {
  if ((x == null) != (y == null)) {
    onUsageError('--x and --y must be provided together.');
  }
  return buildMatcherFromArgs(
    key: key,
    identifier: identifier,
    text: text,
    type: type,
    x: parseCoordinate('--x', x, onUsageError),
    y: parseCoordinate('--y', y, onUsageError),
    ancestorKeys: ancestorKeys,
  );
}
