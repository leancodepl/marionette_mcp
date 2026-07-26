/// Builds a widget matcher map from CLI arguments.
///
/// Accepts named args like --key, --identifier, --text, --type, --x, --y,
/// --within-key and constructs the matcher map expected by
/// [VmServiceConnector].
Map<String, dynamic> buildMatcherFromArgs({
  String? key,
  String? identifier,
  String? text,
  String? type,
  num? x,
  num? y,
  bool focused = false,
  String? withinKey,
}) {
  final matcher = <String, dynamic>{};
  if (key != null) matcher['key'] = key;
  if (identifier != null) matcher['identifier'] = identifier;
  if (text != null) matcher['text'] = text;
  if (type != null) matcher['type'] = type;
  if (x != null) matcher['x'] = x;
  if (y != null) matcher['y'] = y;
  if (focused) matcher['focused'] = true;
  if (withinKey != null) matcher['within_key'] = withinKey;
  return matcher;
}

/// Whether [matcher] identifies an element to act on.
///
/// `within_key` only narrows where the search happens, so a matcher carrying
/// nothing but a scope still selects nothing.
bool hasSelector(Map<String, dynamic> matcher) {
  return matcher.keys.any((field) => field != 'within_key');
}

/// Help text for the `--within-key` option, shared by every matcher-based
/// command.
const withinKeyHelp = 'Limit the search to the subtree of the element with '
    'this key. Use it when the same key appears in several identical '
    'subtrees (grid cells, repeated cards).';
