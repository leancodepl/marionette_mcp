/// Native automation lane: connector interface, element model, and UI-tree
/// parsing shared by Android (UIAutomator2) and iOS (WebDriverAgent)
/// implementations.
library;

/// Rectangle in physical screen pixels, as reported by native automation
/// servers.
///
/// Note this differs from the Flutter lane, which reports logical pixels —
/// coordinates from the two lanes must never be mixed.
class NativeBounds {
  const NativeBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  Map<String, int> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

/// A single element of the native UI hierarchy.
///
/// Produced by [parseAndroidUiDump] / [parseWdaSource] and consumed by
/// [NativeConnector] implementations and the MCP tool layer.
class NativeElement {
  const NativeElement({
    required this.className,
    required this.clickable,
    required this.bounds,
    this.text,
    this.resourceId,
  });

  /// Visible text or accessibility description, if any.
  final String? text;

  /// Android `resource-id` or iOS accessibility identifier (`name`), if any.
  final String? resourceId;

  /// Native class of the element (e.g. `android.widget.Button`,
  /// `XCUIElementTypeButton`).
  final String className;

  /// Whether the platform reports the element as tappable.
  final bool clickable;

  /// On-screen rectangle in physical pixels.
  final NativeBounds bounds;

  /// Center of [bounds] in physical pixels — the natural tap target.
  ({int x, int y}) get center => (
        x: bounds.x + bounds.width ~/ 2,
        y: bounds.y + bounds.height ~/ 2,
      );

  /// JSON shape mirroring the Flutter lane's `get_interactive_elements`
  /// output (`type`, `text`, `id`, `bounds`, `clickable`) so agents can
  /// consume both lanes uniformly.
  Map<String, dynamic> toJson() => {
        'type': className,
        if (text != null) 'text': text,
        if (resourceId != null) 'id': resourceId,
        'bounds': bounds.toJson(),
        'clickable': clickable,
      };
}

/// A connected native automation session (UIAutomator2 on Android,
/// WebDriverAgent on iOS).
///
/// Implementations own the underlying WebDriver session and any device-side
/// processes; [dispose] must release both. All coordinates are physical
/// pixels (see [NativeBounds]).
abstract class NativeConnector {
  /// Returns the interactive/labelled elements currently on screen,
  /// spanning the whole device UI (system dialogs included), not just the
  /// Flutter app.
  Future<List<NativeElement>> getNativeElements();

  /// Identifier of the app currently in the foreground (e.g. Android package
  /// name or iOS bundle id), or null when it cannot be determined.
  ///
  /// There is no standard WebDriver endpoint for this; platform
  /// implementations derive it from platform-specific calls or from the UI
  /// tree itself. Agents use it as a cheap signal for "is a system surface
  /// covering the app".
  Future<String?> get foregroundApp;

  /// Taps [element], typically at its [NativeElement.center].
  Future<void> tapElement(NativeElement element);

  /// Taps at ([x], [y]) in physical pixels.
  Future<void> tapAt(int x, int y);

  /// Focuses [element] and types [text] into it.
  Future<void> enterText(NativeElement element, String text);

  /// Swipes from ([startX], [startY]) to ([endX], [endY]) in physical
  /// pixels over [durationMs] milliseconds.
  Future<void> swipe({
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
  });

  /// Captures a PNG of the full device screen (system dialogs included)
  /// and returns it as a base64-encoded string.
  ///
  /// Unlike the Flutter lane's `take_screenshots`, this captures whatever
  /// is actually on screen — permission dialogs, sheets, status-bar panels —
  /// not just the Flutter view hierarchy.
  Future<String> takeScreenshot();

  /// Ends the session and tears down any resources the connector started.
  Future<void> dispose();
}

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
      final end = xml.indexOf('>', open);
      i = end == -1 ? xml.length : end + 1;
      continue;
    }

    // Find the end of the opening tag, ignoring '>' inside quoted attribute
    // values (legal in XML and possible in text/label attributes).
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

String _decodeXmlEntities(String value) {
  if (!value.contains('&')) return value;
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

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

/// XCUIElementType suffixes WDA reports for elements that are meaningfully
/// tappable/editable; used to derive [NativeElement.clickable], since WDA
/// XML has no direct clickable flag.
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

/// WDA emits integer coordinates, but tolerate decimal strings too.
int _parseWdaInt(String? value) {
  if (value == null) return 0;
  return int.tryParse(value) ?? double.tryParse(value)?.round() ?? 0;
}
