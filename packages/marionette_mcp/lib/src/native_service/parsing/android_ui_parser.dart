import 'package:marionette_mcp/src/native_service/native_models.dart';
import 'package:marionette_mcp/src/native_service/parsing/ui_tree_parser.dart';

final _androidBoundsPattern = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]');

/// Parses a UIAutomator UI dump (Android `page source` XML) into
/// [NativeElement]s.
///
/// Keeps only nodes that are clickable, or carry non-empty text /
/// `content-desc`, or a non-empty `resource-id` — mirroring the Flutter
/// lane's "interactive or meaningful" filter.
List<NativeElement> parseAndroidUiDump(String xml) {
  final nodes = parseUiTree(xml, isRelevant: (attributes) {
    final text = attributes['text'] ?? '';
    final contentDesc = attributes['content-desc'] ?? '';
    final resourceId = attributes['resource-id'] ?? '';
    return attributes['clickable'] == 'true' ||
        text.isNotEmpty ||
        contentDesc.isNotEmpty ||
        resourceId.isNotEmpty;
  });

  return nodes.map((attributes) {
    final text = attributes['text'] ?? '';
    final contentDesc = attributes['content-desc'] ?? '';
    final resourceId = attributes['resource-id'] ?? '';

    return NativeElement(
      className: attributes['class'] ?? attributes[uiNodeTagKey]!,
      text: text.isNotEmpty
          ? text
          : contentDesc.isNotEmpty
              ? contentDesc
              : null,
      resourceId: resourceId.isNotEmpty ? resourceId : null,
      clickable: attributes['clickable'] == 'true',
      bounds: _parseAndroidBounds(attributes['bounds']),
    );
  }).toList();
}

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
