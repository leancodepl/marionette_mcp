import 'package:args/args.dart';
import 'package:marionette_mcp/runtime.dart' show buildMatcher;

export 'package:marionette_mcp/runtime.dart' show hasSelector;

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
  return buildMatcher({
    if (key != null) 'key': key,
    if (identifier != null) 'identifier': identifier,
    if (text != null) 'text': text,
    if (type != null) 'type': type,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (focused) 'focused_element': true,
    if (ancestorKeys.isNotEmpty) 'ancestor_keys': ancestorKeys,
  });
}

/// Parses a finite numeric CLI option without silently discarding invalid input.
num parseFiniteNumber(
  String option,
  String value,
  Never Function(String) fail,
) {
  final number = num.tryParse(value);
  if (number == null || !number.isFinite) {
    fail('--$option must be a finite number, got "$value".');
  }
  return number;
}

/// Builds a matcher after validating the command's targeting options.
///
/// Element selectors may be combined, but coordinate and focused targeting
/// cannot be combined with another targeting mode. Ancestor scope retains its
/// existing wire representation, including when the target ignores that scope.
Map<String, dynamic> buildValidatedMatcherFromArgs(
  ArgResults? args, {
  required Never Function(String) fail,
}) {
  String? option(String name) =>
      args?.options.contains(name) == true ? args![name] as String? : null;

  final key = option('key');
  final identifier = option('identifier');
  final text = option('text');
  final type = option('type');
  final xText = option('x');
  final yText = option('y');
  if ((xText == null) != (yText == null)) {
    fail('--x and --y must be provided together.');
  }
  final x = xText == null ? null : parseFiniteNumber('x', xText, fail);
  final y = yText == null ? null : parseFiniteNumber('y', yText, fail);
  final focused =
      args?.options.contains('focused') == true && args!['focused'] == true;
  final hasElement =
      key != null || identifier != null || text != null || type != null;
  if (x != null && (hasElement || focused)) {
    fail('Cannot mix --x/--y with element or focused selectors.');
  }
  if (focused && hasElement) {
    fail('Cannot mix --focused with --key, --identifier, --text, or --type.');
  }
  return buildMatcherFromArgs(
    key: key,
    identifier: identifier,
    text: text,
    type: type,
    x: x,
    y: y,
    focused: focused,
    ancestorKeys: args?.options.contains('ancestor-keys') == true
        ? args!['ancestor-keys'] as List<String>
        : const [],
  );
}
