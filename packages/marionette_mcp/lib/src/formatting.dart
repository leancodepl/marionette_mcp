import 'dart:convert';

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
      additionalProps.add('$key: ${_formatValue(value)}');
    }
  });

  if (additionalProps.isNotEmpty) {
    buffer.write(', ${additionalProps.join(', ')}');
  }

  return buffer.toString();
}

/// Formats a value for display.
String _formatValue(dynamic value) {
  if (value is String) {
    return '"$value"';
  }
  if (value is Map || value is List) {
    return jsonEncode(value);
  }
  return value.toString();
}
