/// Minimal XML UI-tree parsing shared by Android (UIAutomator) and iOS (WDA).
library;

/// Key under which [parseUiTree] stores each node's tag name in its
/// attribute map, chosen so it cannot collide with real XML attribute names.
const uiNodeTagKey = '#tag';

/// Parses [xml] and returns the attribute maps of all nodes for which
/// [isRelevant] returns true, in document order. Each map additionally
/// contains the node's tag name under [uiNodeTagKey].
///
/// This is a deliberately minimal parser for machine-generated UI dumps
/// (UIAutomator `page source`, WDA source XML) that avoids adding an XML
/// package dependency. It handles nested and self-closing tags, single- and
/// double-quoted attribute values, and the five predefined entities
/// (`&amp;` `&lt;` `&gt;` `&quot;` `&apos;`). It does NOT handle CDATA
/// sections, other entities, or DTDs — acceptable because both servers emit
/// plain escaped XML. Malformed input yields best-effort results rather
/// than throwing.
List<Map<String, String>> parseUiTree(
  String xml, {
  required bool Function(Map<String, String> attributes) isRelevant,
}) {
  final nodes = <Map<String, String>>[];
  var i = 0;

  while (i < xml.length) {
    final open = xml.indexOf('<', i);
    if (open == -1) break;

    if (xml.startsWith('<?', open)) {
      final end = xml.indexOf('?>', open);
      i = end == -1 ? xml.length : end + 2;
      continue;
    }
    if (xml.startsWith('<!--', open)) {
      final end = xml.indexOf('-->', open);
      i = end == -1 ? xml.length : end + 3;
      continue;
    }
    if (xml.startsWith('<!', open) || xml.startsWith('</', open)) {
      final end = xml.indexOf('>', open);
      i = end == -1 ? xml.length : end + 1;
      continue;
    }

    final close = _findTagEnd(xml, open + 1);
    if (close == -1) break;

    final tagContent = xml.substring(open + 1, close);
    final attributes = _parseTag(tagContent);
    if (attributes != null && isRelevant(attributes)) {
      nodes.add(attributes);
    }

    i = close + 1;
  }

  return nodes;
}

int _findTagEnd(String xml, int from) {
  var i = from;
  while (i < xml.length) {
    final char = xml.codeUnitAt(i);
    if (char == 0x3E) return i;
    if (char == 0x22 || char == 0x27) {
      final closeQuote = xml.indexOf(String.fromCharCode(char), i + 1);
      if (closeQuote == -1) return -1;
      i = closeQuote + 1;
    } else {
      i++;
    }
  }
  return -1;
}

final _attributePattern =
    RegExp('([^\\s=/>]+)\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')');

Map<String, String>? _parseTag(String tagContent) {
  final content = tagContent.endsWith('/')
      ? tagContent.substring(0, tagContent.length - 1)
      : tagContent;

  final nameMatch = RegExp(r'^\s*([^\s/>]+)').firstMatch(content);
  if (nameMatch == null) return null;

  final attributes = <String, String>{uiNodeTagKey: nameMatch.group(1)!};
  for (final match in _attributePattern.allMatches(content, nameMatch.end)) {
    attributes[match.group(1)!] =
        decodeXmlEntities(match.group(2) ?? match.group(3) ?? '');
  }
  return attributes;
}

/// Decodes the five XML entities UIAutomator and WDA emit in page source.
String decodeXmlEntities(String value) {
  if (!value.contains('&')) return value;
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
