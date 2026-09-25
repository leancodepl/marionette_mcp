import 'dart:convert';

/// Shared description of the `ancestor_keys` field across every matcher-based
/// tool.
///
/// Kept short on purpose: it is repeated in every schema, so its length is
/// paid on every connection. The full contract — strict nesting, the failure
/// rule, the `scroll_to` timing, what ignores the field — is stated once in
/// the server instructions.
const ancestorKeysDescription =
    'Optional wrapper keys (ValueKey<String>), outermost first; each is '
    'looked up inside the previous one. Limits the search to that subtree. '
    'Fails if a key has no element.';

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
