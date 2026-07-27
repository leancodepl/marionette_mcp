import 'dart:convert';

/// Shared description of the `ancestor_keys` field across every matcher-based
/// tool, so agents read the same contract wherever they discover it.
const ancestorKeysDescription =
    'Optional. Restricts the search to the subtree of the element whose key '
    '(a ValueKey<String>) is this value. Use it when the same inner key '
    'appears in several identical subtrees — grid cells, repeated cards, '
    'embedded app instances — to pick the one you mean, e.g. '
    '{"key": "cell.joinButton", "ancestor_keys": ["grid.cell_2"]}. List the '
    'keys outermost first to go deeper: each one is looked up inside the '
    'subtree of the previous, so ["session_2", "grid.cell_3"] reaches a cell '
    'whose own key also repeats in other sessions. Fails if any of these keys '
    'has no element; ignored when matching by coordinates or focused_element.';

/// `ancestor_keys` as worded for `get_interactive_elements`, which lists a
/// subtree rather than matching one element inside it.
///
/// Kept separate from [ancestorKeysDescription] so neither has to carry a
/// caveat that does not apply to it: this tool has no coordinates or
/// focused_element selectors to be ignored by.
const ancestorKeysListDescription =
    'Optional. Lists only the elements inside the subtree named by these '
    'wrapper keys (each a ValueKey<String>), instead of the whole screen. Use '
    'it to cut the output down on a screen that repeats the same subtree — '
    'grid cells, repeated cards, embedded app instances — e.g. '
    '["grid.cell_2"]. The keys nest, outermost first: each is looked up '
    'inside the subtree of the previous, so ["session_2", "grid.cell_3"] '
    'reaches a cell whose own key also repeats. The same list can then be '
    'passed as ancestor_keys to tap, enter_text and the other tools to act '
    'inside that subtree. Fails if any of these keys has no element.';

/// Builds a widget matcher map from tool/CLI arguments.
///
/// Supports matching by key, identifier, text, type, and coordinates, plus the
/// optional `ancestor_keys` scope.
Map<String, dynamic> buildMatcher(Map<String, dynamic> args) {
  final matcher = <String, dynamic>{};
  if (args['focused_element'] == true) {
    matcher['focused'] = true;
  }
  // Flatten coordinates for VM service (which only supports string->string)
  if (args['coordinates'] case final Map<String, dynamic> coordinates) {
    matcher['x'] = coordinates['x'];
    matcher['y'] = coordinates['y'];
  }
  if (args.containsKey('key')) {
    matcher['key'] = args['key'];
  }
  if (args.containsKey('identifier')) {
    matcher['identifier'] = args['identifier'];
  }
  if (args.containsKey('text')) {
    matcher['text'] = args['text'];
  }
  if (args.containsKey('type')) {
    matcher['type'] = args['type'];
  }
  if (args.containsKey('x')) {
    matcher['x'] = args['x'];
  }
  if (args.containsKey('y')) {
    matcher['y'] = args['y'];
  }
  // The VM service only carries string values, so the scope chain travels
  // JSON-encoded rather than as a list (whose toString() is un-parseable) or
  // a delimited string (whose delimiter could appear inside a key).
  if (args['ancestor_keys'] case final List<dynamic> ancestorKeys
      when ancestorKeys.isNotEmpty) {
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

/// Formats an element map for human-readable display.
String formatElement(Map<String, dynamic> element) {
  final buffer = StringBuffer();

  // Element type
  if (element['type'] != null) {
    buffer.write('Type: ${element['type']}');
  }

  // Key
  if (element['key'] != null) {
    buffer.write(', Key: "${element['key']}"');
  }

  // Text content
  if (element['text'] != null && element['text'] != '') {
    buffer.write(', Text: "${element['text']}"');
  }

  // Additional properties
  final additionalProps = <String>[];
  element.forEach((key, value) {
    if (key != 'type' && key != 'key' && key != 'text' && value != null) {
      additionalProps.add('$key: ${formatValue(value)}');
    }
  });

  if (additionalProps.isNotEmpty) {
    buffer.write(', ${additionalProps.join(', ')}');
  }

  return buffer.toString();
}

/// Formats a value for human-readable display.
String formatValue(dynamic value) {
  if (value is String) {
    return '"$value"';
  }
  if (value is Map || value is List) {
    return jsonEncode(value);
  }
  return value.toString();
}
