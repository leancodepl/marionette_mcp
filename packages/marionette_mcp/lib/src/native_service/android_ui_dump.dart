import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/ui_tree.dart';

final _androidBoundsPattern = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]');

/// Whether [className] is a text field: `EditText` and its subclasses
/// (Flutter and Compose fields report `android.widget.EditText`; Material's
/// `TextInputEditText`, `AutoCompleteTextView`).
bool isAndroidEditableClass(String className) =>
    className.contains('EditText') ||
    className.contains('AutoCompleteTextView');

/// Parses a UIAutomator UI dump (Android `page source` XML) into
/// [NativeElement]s.
///
/// Keeps only nodes that are clickable, or carry non-empty text /
/// `content-desc` / `hint`, or a non-empty `resource-id` — mirroring the
/// Flutter lane's "interactive or meaningful" filter.
///
/// [NativeElement.text] is the first non-empty of `text`, `content-desc` and
/// `hint`. For a text field the order is `hint`, `content-desc`, `text`: the
/// field keeps its label (Flutter puts the label in `hint`) whether or not
/// it has content, and the content goes to [NativeElement.value] — the same
/// split as on iOS, so a selector for a field still matches after typing.
List<NativeElement> parseAndroidUiDump(String xml) {
  bool isEditable(Map<String, String> attributes) =>
      isAndroidEditableClass(attributes['class'] ?? '');

  String? visibleText(Map<String, String> attributes) {
    final keys = isEditable(attributes)
        ? const ['hint', 'content-desc', 'text']
        : const ['text', 'content-desc', 'hint'];
    for (final key in keys) {
      final value = attributes[key] ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  final nodes = parseUiTree(xml, isRelevant: (attributes) {
    final resourceId = attributes['resource-id'] ?? '';
    return attributes['clickable'] == 'true' ||
        attributes['scrollable'] == 'true' ||
        visibleText(attributes) != null ||
        resourceId.isNotEmpty;
  }).map((node) => node.attributes);

  return nodes.map((node) {
    // A WebView password field reports its content in clear text; mask it
    // like iOS does for a secure field, one bullet per character.
    final password = node['text'] ?? '';
    final attributes = node['password'] == 'true' && password.isNotEmpty
        ? {...node, 'text': '•' * password.runes.length}
        : node;
    final resourceId = attributes['resource-id'] ?? '';
    final className = attributes['class'] ?? attributes[uiNodeTagKey]!;
    final rawText = attributes['text'] ?? '';
    // An editable field's `text` is its content, unless it is showing the
    // hint (`showing-hint`, Android 8+).
    final value = isEditable(attributes) &&
            rawText.isNotEmpty &&
            attributes['showing-hint'] != 'true' &&
            rawText != attributes['hint']
        ? rawText
        : null;

    return NativeElement(
      className: className,
      text: visibleText(attributes),
      resourceId: resourceId.isNotEmpty ? resourceId : null,
      clickable: attributes['clickable'] == 'true',
      bounds: _parseAndroidBounds(attributes['bounds']),
      value: value,
      enabled: attributes['enabled'] != 'false',
      focused: attributes['focused'] == 'true',
      checked: attributes['checkable'] == 'true'
          ? attributes['checked'] == 'true'
          : null,
      selected: attributes['selected'] == 'true',
      scrollable: attributes['scrollable'] == 'true',
    );
  }).toList();
}

/// Parses the UIAutomator `[x1,y1][x2,y2]` bounds format. Returns a zero
/// rect when missing or malformed.
NativeBounds _parseAndroidBounds(String? bounds) {
  final match =
      bounds == null ? null : _androidBoundsPattern.firstMatch(bounds);
  if (match == null) {
    return const NativeBounds(x: 0, y: 0, width: 0, height: 0);
  }
  final x1 = int.parse(match.group(1)!);
  final y1 = int.parse(match.group(2)!);
  final x2 = int.parse(match.group(3)!);
  final y2 = int.parse(match.group(4)!);
  return NativeBounds(x: x1, y: y1, width: x2 - x1, height: y2 - y1);
}
