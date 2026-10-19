/// Native automation lane: connector interface, element model, and UI-tree
/// parsing shared by Android (UIAutomator2) and iOS (WebDriverAgent)
/// implementations.
library;

import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_key.dart';

export 'package:marionette_mcp/src/native_service/native_device.dart';
export 'package:marionette_mcp/src/native_service/native_key.dart';

/// Screen orientation, as named by W3C WebDriver.
enum NativeOrientation {
  portrait('PORTRAIT'),
  landscape('LANDSCAPE');

  const NativeOrientation(this.wireName);

  /// Value of the WebDriver `orientation` endpoint.
  final String wireName;

  static NativeOrientation? tryParse(Object? raw) {
    final normalized = raw is String ? raw.toLowerCase().trim() : null;
    for (final value in values) {
      if (value.name == normalized) return value;
    }
    return null;
  }
}

/// Rectangle in **screenshot pixels**: the pixel grid of the image returned
/// by `native_take_screenshot`, on every platform.
///
/// Servers that work in other units (WebDriverAgent uses points) are
/// converted by the connector; see docs/native-lane-decisions.md#d2. This
/// differs from the Flutter lane, which reports logical pixels — coordinates
/// from the two lanes must never be mixed.
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

  /// These bounds multiplied by [factor], rounded to whole pixels.
  NativeBounds scaled(double factor) {
    if (factor == 1) return this;
    int scale(int value) => (value * factor).round();
    return NativeBounds(
      x: scale(x),
      y: scale(y),
      width: scale(width),
      height: scale(height),
    );
  }

  Map<String, int> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

/// Size of the device screen in screenshot pixels, plus how many
/// screenshot pixels make up one server unit ([scale]; 1 on Android, the
/// display scale such as 3 on iOS, where WebDriverAgent works in points).
class NativeScreen {
  const NativeScreen({
    required this.width,
    required this.height,
    required this.scale,
  });

  final int width;
  final int height;
  final double scale;

  Map<String, Object> toJson() => {
        'width': width,
        'height': height,
        'scale': scale,
      };
}

/// A single element of the native UI hierarchy.
///
/// State fields and the label / content split of text fields are described
/// in docs/native-lane-decisions.md#d15. Produced by [parseAndroidUiDump] / [parseWdaSource] and consumed by
/// [NativeConnector] implementations and the MCP tool layer.
class NativeElement {
  const NativeElement({
    required this.className,
    required this.clickable,
    required this.bounds,
    this.text,
    this.resourceId,
    this.value,
    this.enabled = true,
    this.focused,
    this.checked,
    this.selected = false,
    this.scrollable = false,
  });

  /// Visible text or accessibility description, if any. For an empty text
  /// field this is its placeholder / hint.
  final String? text;

  /// Android `resource-id` or iOS accessibility identifier (`name`), if any.
  final String? resourceId;

  /// Native class of the element (e.g. `android.widget.Button`,
  /// `XCUIElementTypeButton`).
  final String className;

  /// Whether the platform reports the element as tappable.
  final bool clickable;

  /// On-screen rectangle in screenshot pixels.
  final NativeBounds bounds;

  /// Content of an editable field (what was typed), when it differs from a
  /// placeholder. Null for empty fields and non-editable elements. On iOS a
  /// Flutter field's [text] is its label, so this is the only place its
  /// content appears.
  final String? value;

  /// False for disabled controls.
  final bool enabled;

  /// Whether the element has input focus; null when the platform does not
  /// report focus (iOS).
  final bool? focused;

  /// On/off state of a switch, checkbox or radio button; null for elements
  /// that cannot be checked.
  final bool? checked;

  /// Whether the element is selected (e.g. the current tab).
  final bool selected;

  /// Whether the element is a scrollable container (useful as `within` for
  /// native_scroll).
  final bool scrollable;

  /// This element with [bounds] multiplied by [factor] (see
  /// [NativeBounds.scaled]).
  NativeElement scaled(double factor) => factor == 1
      ? this
      : NativeElement(
          className: className,
          clickable: clickable,
          bounds: bounds.scaled(factor),
          text: text,
          resourceId: resourceId,
          value: value,
          enabled: enabled,
          focused: focused,
          checked: checked,
          selected: selected,
          scrollable: scrollable,
        );

  /// Whether the element occupies screen space. Flutter on iOS keeps
  /// off-screen semantics nodes in the tree with zero-size bounds at (0, 0);
  /// those are not visible (docs/native-lane-decisions.md#d16).
  bool get isVisible => bounds.width > 0 && bounds.height > 0;

  /// Center of [bounds] in screenshot pixels — the natural tap target.
  ({int x, int y}) get center => (
        x: bounds.x + bounds.width ~/ 2,
        y: bounds.y + bounds.height ~/ 2,
      );

  /// JSON shape mirroring the Flutter lane's `get_interactive_elements`
  /// output (`type`, `text`, `id`, `bounds`, `clickable`) so agents can
  /// consume both lanes uniformly. State fields are only included when they
  /// carry information (not default), to keep the output small.
  Map<String, dynamic> toJson() => {
        'type': className,
        if (text != null) 'text': text,
        if (value != null) 'value': value,
        if (resourceId != null) 'id': resourceId,
        'bounds': bounds.toJson(),
        'clickable': clickable,
        if (!enabled) 'enabled': false,
        if (focused == true) 'focused': true,
        if (checked != null) 'checked': checked,
        if (selected) 'selected': true,
        if (scrollable) 'scrollable': true,
      };
}

/// Prepares a device-side WebDriver server (UIAutomator2 / WebDriverAgent)
/// and tears it down again.
///
/// Connectors depend on this interface rather than on the concrete
/// bootstraps so tests can point them at a fake server.
abstract interface class NativeServerBootstrap {
  /// Starts the server if needed and returns its local base URL.
  Future<Uri> ensureServerReady();

  /// Stops whatever [ensureServerReady] started. Best-effort; never throws.
  Future<void> dispose();
}

/// A connected native automation session (UIAutomator2 on Android,
/// WebDriverAgent on iOS).
///
/// Implementations own the underlying WebDriver session and any device-side
/// processes; [dispose] must release both. All coordinates, in and out, are
/// screenshot pixels (see [NativeBounds]).
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

  /// Taps at ([x], [y]) in screenshot pixels.
  Future<void> tapAt(int x, int y);

  /// Focuses [element] and types [text] into it; [clear] empties the field
  /// first.
  Future<void> enterText(
    NativeElement element,
    String text, {
    bool clear = false,
  });

  /// Types [text] into the field that currently has keyboard focus; [clear]
  /// empties it first. Throws `NativeElementNotFoundException` when no field
  /// is focused.
  Future<void> typeText(String text, {bool clear = false});

  /// Presses a system / hardware [key]. Throws `NativeUnsupportedException`
  /// for keys the platform does not have.
  Future<void> pressKey(NativeKey key);

  /// Whether the software keyboard is currently shown.
  Future<bool> isKeyboardShown();

  /// Hides the software keyboard; returns false when it was not shown.
  Future<bool> hideKeyboard();

  /// Swipes from ([startX], [startY]) to ([endX], [endY]) in screenshot
  /// pixels over [durationMs] milliseconds.
  ///
  /// With [holdMs] > 0 the finger rests at the end for that long before
  /// lifting, so the content moves exactly the swipe distance without a
  /// fling.
  Future<void> swipe({
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
    int holdMs = 0,
  });

  /// Presses at ([x], [y]) in screenshot pixels and holds for [durationMs].
  Future<void> longPress(int x, int y, {int durationMs = 600});

  /// Taps twice at ([x], [y]) with [delayMs] between the taps.
  Future<void> doubleTap(int x, int y, {int delayMs = 100});

  /// Two-finger pinch centered on ([centerX], [centerY]): the fingers start
  /// [startSpan] screenshot pixels apart (horizontally) and move to
  /// [endSpan] apart over [durationMs]. `endSpan > startSpan` zooms in.
  Future<void> pinch({
    required int centerX,
    required int centerY,
    required int startSpan,
    required int endSpan,
    int durationMs = 500,
  });

  /// Captures a PNG of just [element] (base64), in screenshot pixels.
  Future<String> takeElementScreenshot(NativeElement element);

  /// Captures a PNG of the full device screen (system dialogs included)
  /// and returns it as a base64-encoded string.
  ///
  /// Unlike the Flutter lane's `take_screenshots`, this captures whatever
  /// is actually on screen — permission dialogs, sheets, status-bar panels —
  /// not just the Flutter view hierarchy.
  Future<String> takeScreenshot();

  /// Current screen size in screenshot pixels and the server-unit scale.
  Future<NativeScreen> getScreen();

  /// Current screen orientation.
  Future<NativeOrientation> getOrientation();

  /// Rotates the screen to [orientation]; [getScreen] and element bounds
  /// follow the new orientation.
  Future<void> setOrientation(NativeOrientation orientation);

  /// Operations on the device that do not use the UI session (permissions,
  /// app lifecycle, URLs …); see docs/native-lane-decisions.md#d12.
  NativeDevice get device;

  /// Whether the device-side server answers a health check right now.
  ///
  /// Never throws; a slow or dead server reports false. Used before actions
  /// to tell "the server was already gone" (safe to reconnect and act) from
  /// "the connection broke while acting" (see
  /// docs/native-lane-decisions.md#d3).
  Future<bool> isServerResponding();

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
/// double-quoted attribute values, the five predefined entities
/// (`&amp;` `&lt;` `&gt;` `&quot;` `&apos;`) and numeric character
/// references (`&#10;`, `&#x2019;`). It does NOT handle CDATA sections,
/// other named entities, or DTDs — acceptable because both servers emit
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

final _androidBoundsPattern = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]');

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
  bool isField(Map<String, String> attributes) {
    final className = attributes['class'] ?? '';
    return className.contains('EditText') ||
        className.contains('AutoCompleteTextView');
  }

  String? visibleText(Map<String, String> attributes) {
    final keys = isField(attributes)
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
  });

  return nodes.map((attributes) {
    final resourceId = attributes['resource-id'] ?? '';
    final className = attributes['class'] ?? attributes[uiNodeTagKey]!;
    final rawText = attributes['text'] ?? '';
    // An editable field's `text` is its content, unless it is showing the
    // hint (`showing-hint`, Android 8+).
    final value = isField(attributes) &&
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

/// XCUIElementType suffixes WDA reports for elements that are meaningfully
/// tappable/editable; used to derive [NativeElement.clickable], since WDA
/// XML has no direct clickable flag.
const _wdaInteractiveTypes = {
  'Button',
  'Key', // software keyboard keys

  'Cell',
  'TextField',
  'SecureTextField',
  'Switch',
  'Link',
  'SearchField',
};

const _wdaTypePrefix = 'XCUIElementType';

/// XCUI types whose `value` is an on/off state (`"1"` / `"0"`).
const _wdaToggleTypes = {'Switch', 'CheckBox', 'Toggle'};

/// XCUI text-entry types.
const _wdaFieldTypes = {
  'TextField',
  'SecureTextField',
  'TextView',
  'SearchField',
};

/// XCUI types whose `value` is user content worth reporting.
const _wdaValueTypes = {..._wdaFieldTypes, 'Slider'};

/// XCUI container types that scroll.
const _wdaScrollableTypes = {'ScrollView', 'Table', 'CollectionView'};

/// Parses WebDriverAgent source XML (tags named `XCUIElementType*`) into
/// [NativeElement]s.
///
/// `label` (falling back to `value`; for text fields to `placeholderValue`
/// first) maps to [NativeElement.text], `name`
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

  // A field is named by its label, else its placeholder; its content is
  // reported as `value` (see below), so typing does not rename it.
  String? textOf(Map<String, String> attributes) {
    final tag = attributes[uiNodeTagKey]!;
    final isField = tag.startsWith(_wdaTypePrefix) &&
        _wdaFieldTypes.contains(tag.substring(_wdaTypePrefix.length));
    final keys = isField
        ? const ['label', 'placeholderValue', 'value']
        : const ['label', 'value'];
    for (final key in keys) {
      final text = attributes[key] ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  final nodes = parseUiTree(xml, isRelevant: (attributes) {
    if (!attributes[uiNodeTagKey]!.startsWith(_wdaTypePrefix)) return false;
    final name = attributes['name'] ?? '';
    final tag = attributes[uiNodeTagKey]!;
    return isClickable(attributes) ||
        textOf(attributes) != null ||
        name.isNotEmpty ||
        _wdaScrollableTypes.contains(tag.substring(_wdaTypePrefix.length));
  });

  return nodes.map((attributes) {
    final name = attributes['name'] ?? '';
    final tag = attributes[uiNodeTagKey]!;
    final type = tag.startsWith(_wdaTypePrefix)
        ? tag.substring(_wdaTypePrefix.length)
        : tag;
    final rawValue = attributes['value'] ?? '';
    final isToggle = _wdaToggleTypes.contains(type);
    // Other types use `value` for unrelated state (a selected tab button
    // reports "1"), and an empty field reports its placeholder as `value`.
    final value = _wdaValueTypes.contains(type) &&
            rawValue.isNotEmpty &&
            rawValue != attributes['placeholderValue']
        ? rawValue
        : null;

    return NativeElement(
      className: tag,
      text: textOf(attributes),
      resourceId: name.isNotEmpty ? name : null,
      clickable: isClickable(attributes),
      bounds: NativeBounds(
        x: _parseWdaInt(attributes['x']),
        y: _parseWdaInt(attributes['y']),
        width: _parseWdaInt(attributes['width']),
        height: _parseWdaInt(attributes['height']),
      ),
      value: value,
      enabled: attributes['enabled'] != 'false',
      checked: isToggle ? rawValue == '1' : null,
      selected: (attributes['traits'] ?? '').contains('Selected'),
      scrollable: _wdaScrollableTypes.contains(type),
    );
  }).toList();
}

/// WDA emits integer coordinates, but tolerate decimal strings too.
int _parseWdaInt(String? value) {
  if (value == null) return 0;
  return int.tryParse(value) ?? double.tryParse(value)?.round() ?? 0;
}
