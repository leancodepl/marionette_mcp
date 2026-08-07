import 'package:marionette_mcp/src/native_service/native_models.dart';
import 'package:marionette_mcp/src/native_service/parsing/ui_tree_parser.dart';

const _wdaInteractiveTypes = {
  'Button',
  'Cell',
  'TextField',
  'SecureTextField',
  'Switch',
  'Link',
  'SearchField',
};

const _wdaTypePrefix = 'XCUIElementType';

/// Parses WebDriverAgent source XML (tags named `XCUIElementType*`) into
/// [NativeElement]s.
///
/// `label` (falling back to `value`) maps to [NativeElement.text], `name`
/// to [NativeElement.resourceId], and the tag name to
/// [NativeElement.className]. An element counts as clickable when it is
/// enabled and its type is one of the typical interactive XCUI types.
/// Filtering matches [parseAndroidUiDump]: clickable, or non-empty text, or
/// non-empty identifier.
List<NativeElement> parseWdaSource(String xml) {
  bool isClickable(Map<String, String> attributes) {
    final tag = attributes[uiNodeTagKey]!;
    final type = tag.startsWith(_wdaTypePrefix)
        ? tag.substring(_wdaTypePrefix.length)
        : tag;
    return attributes['enabled'] == 'true' &&
        _wdaInteractiveTypes.contains(type);
  }

  String? textOf(Map<String, String> attributes) {
    final label = attributes['label'] ?? '';
    if (label.isNotEmpty) return label;
    final value = attributes['value'] ?? '';
    if (value.isNotEmpty) return value;
    return null;
  }

  final nodes = parseUiTree(xml, isRelevant: (attributes) {
    if (!attributes[uiNodeTagKey]!.startsWith(_wdaTypePrefix)) return false;
    final name = attributes['name'] ?? '';
    return isClickable(attributes) ||
        textOf(attributes) != null ||
        name.isNotEmpty;
  });

  return nodes.map((attributes) {
    final name = attributes['name'] ?? '';
    return NativeElement(
      className: attributes[uiNodeTagKey]!,
      text: textOf(attributes),
      resourceId: name.isNotEmpty ? name : null,
      clickable: isClickable(attributes),
      bounds: NativeBounds(
        x: _parseWdaInt(attributes['x']),
        y: _parseWdaInt(attributes['y']),
        width: _parseWdaInt(attributes['width']),
        height: _parseWdaInt(attributes['height']),
      ),
    );
  }).toList();
}

int _parseWdaInt(String? value) {
  if (value == null) return 0;
  return int.tryParse(value) ?? double.tryParse(value)?.round() ?? 0;
}
