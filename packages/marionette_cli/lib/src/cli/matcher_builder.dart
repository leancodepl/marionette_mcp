import 'dart:convert';

/// Builds a widget matcher map from CLI arguments.
///
/// Accepts named args like --key, --identifier, --text, --type, --x, --y,
/// --ancestor-key and constructs the matcher map expected by
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

/// Help text for the `--ancestor-key` option, shared by every matcher-based
/// command.
const ancestorKeyHelp = 'Limit the search to the subtree of the element with '
    'this key. Use it when the same key appears in several identical '
    'subtrees (grid cells, repeated cards). Repeat the option, outermost '
    'wrapper first, to go deeper: each key is looked up inside the previous '
    "one's subtree.";
