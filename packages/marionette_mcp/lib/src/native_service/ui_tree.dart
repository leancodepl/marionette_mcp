/// Minimal XML parser for the UI trees the native servers return.
library;

import 'package:marionette_mcp/src/native_service/native_connector.dart';

/// Key under which [parseUiTree] stores each node's tag name in its
/// attribute map, chosen so it cannot collide with real XML attribute names.
const uiNodeTagKey = '#tag';

/// A node [parseUiTree] returns: its attributes, and the clip of its
/// viewport ancestors (null when none clips it).
typedef UiNode = ({Map<String, String> attributes, NativeBounds? clip});

/// Parses [xml] and returns all nodes for which [isRelevant] returns true,
/// in document order. Each node's attributes additionally contain its tag
/// name under [uiNodeTagKey].
///
/// This is a deliberately minimal parser for machine-generated UI dumps
/// (UIAutomator `page source`, WDA source XML) that avoids adding an XML
/// package dependency. It handles nested and self-closing tags, single- and
/// double-quoted attribute values, the five predefined entities
/// (`&amp;` `&lt;` `&gt;` `&quot;` `&apos;`) and numeric character
/// references (`&#10;`, `&#x2019;`). It does NOT handle CDATA sections,
/// other named entities, or DTDs — acceptable because both servers emit
/// plain escaped XML. Malformed input yields partial results rather than
/// throwing.
///
/// With [viewportOf], a node that it maps to bounds clips its descendants:
/// each relevant node inside one or more such ancestors gets the
/// intersection of their bounds as its clip.
///
/// With [adjust], each node's attributes are rewritten before anything else
/// sees them, given the already adjusted attributes of its parent element
/// (null for the root).
List<UiNode> parseUiTree(
  String xml, {
  required bool Function(Map<String, String> attributes) isRelevant,
  NativeBounds? Function(Map<String, String> attributes)? viewportOf,
  Map<String, String> Function(
    Map<String, String> attributes,
    Map<String, String>? parent,
  )? adjust,
}) {
  final nodes = <UiNode>[];
  // Clip in effect inside each open element (null: no viewport ancestor).
  final clips = <NativeBounds?>[];
  // Adjusted attributes of each open element, for [adjust].
  final parents = <Map<String, String>?>[];
  var i = 0;

  while (i < xml.length) {
    final open = xml.indexOf('<', i);
    if (open == -1) break;

    // Skip declarations, comments, DTDs, and closing tags.
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
      if (xml.startsWith('</', open) && clips.isNotEmpty) {
        clips.removeLast();
        parents.removeLast();
      }
      final end = xml.indexOf('>', open);
      i = end == -1 ? xml.length : end + 1;
      continue;
    }

    // Find the end of the opening tag, ignoring '>' inside quoted attribute
    // values (legal in XML and possible in text/label attributes).
    final close = _findTagEnd(xml, open + 1);
    if (close == -1) break;

    final tagContent = xml.substring(open + 1, close);
    final parsed = _parseTag(tagContent);
    final attributes = parsed == null || adjust == null
        ? parsed
        : adjust(parsed, parents.lastOrNull);
    final clip = clips.lastOrNull;
    if (attributes != null && isRelevant(attributes)) {
      nodes.add((attributes: attributes, clip: clip));
    }
    if (!tagContent.endsWith('/')) {
      final viewport = attributes == null ? null : viewportOf?.call(attributes);
      clips.add(
        viewport == null
            ? clip
            : clip == null
                ? viewport
                : clip.intersection(viewport),
      );
      parents.add(attributes);
    }

    i = close + 1;
  }

  return nodes;
}

/// Returns the index of the tag-closing '>' starting the search at [from],
/// skipping over quoted attribute values. Returns -1 when unterminated.
int _findTagEnd(String xml, int from) {
  var i = from;
  while (i < xml.length) {
    final char = xml.codeUnitAt(i);
    if (char == 0x3E) return i; // '>'
    if (char == 0x22 || char == 0x27) {
      // '"' or "'"
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

/// Parses the inside of an opening tag (`name attr="v" ...`, without the
/// angle brackets) into an attribute map including [uiNodeTagKey]. Returns
/// null for tags without a valid name.
Map<String, String>? _parseTag(String tagContent) {
  final content = tagContent.endsWith('/')
      ? tagContent.substring(0, tagContent.length - 1)
      : tagContent;

  final nameMatch = RegExp(r'^\s*([^\s/>]+)').firstMatch(content);
  if (nameMatch == null) return null;

  final attributes = <String, String>{uiNodeTagKey: nameMatch.group(1)!};
  for (final match in _attributePattern.allMatches(content, nameMatch.end)) {
    attributes[match.group(1)!] =
        _decodeXmlEntities(match.group(2) ?? match.group(3) ?? '');
  }
  return attributes;
}

const _namedXmlEntities = {
  'quot': '"',
  'apos': "'",
  'lt': '<',
  'gt': '>',
  'amp': '&',
};

final _xmlEntityPattern = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-z]+);');

/// Decodes the predefined XML entities and numeric character references
/// (`&#10;`, `&#x2019;`) in a single pass, so `&amp;#10;` stays `&#10;`.
/// Unknown or invalid references are kept verbatim.
String _decodeXmlEntities(String value) {
  if (!value.contains('&')) return value;
  return value.replaceAllMapped(_xmlEntityPattern, (match) {
    final entity = match.group(1)!;
    if (!entity.startsWith('#')) {
      return _namedXmlEntities[entity] ?? match.group(0)!;
    }
    final codePoint = entity.startsWith('#x')
        ? int.tryParse(entity.substring(2), radix: 16)
        : int.tryParse(entity.substring(1));
    if (codePoint == null || codePoint > 0x10FFFF) return match.group(0)!;
    return String.fromCharCode(codePoint);
  });
}
