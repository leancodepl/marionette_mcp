import 'dart:convert';

/// Builds a widget matcher map from tool/CLI arguments.
///
/// Supports matching by key, text, type, and coordinates.
Map<String, dynamic> buildMatcher(Map<String, dynamic> args) {
  final matcher = <String, dynamic>{};
  // Flatten coordinates for VM service (which only supports string->string)
  if (args['coordinates'] case final Map<String, dynamic> coordinates) {
    matcher['x'] = coordinates['x'];
    matcher['y'] = coordinates['y'];
  }
  if (args.containsKey('key')) {
    matcher['key'] = args['key'];
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
  return matcher;
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
