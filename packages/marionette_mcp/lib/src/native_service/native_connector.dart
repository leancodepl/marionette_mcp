/// Native automation lane: connector interface, element model, and UI-tree
/// parsing shared by Android (UIAutomator2) and iOS (WebDriverAgent)
/// implementations.
library;

import 'dart:convert' show jsonEncode;
import 'dart:math' show max, min;

import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_key.dart';

export 'package:marionette_mcp/src/native_service/native_device.dart';
export 'package:marionette_mcp/src/native_service/native_key.dart';

/// Rectangle in **screenshot pixels**: the pixel grid of the image returned
/// by `native_take_screenshot`, on every platform.
///
/// Servers that work in other units (WebDriverAgent uses points) are
/// converted by the connector. This
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
/// Produced by [parseAndroidUiDump] / [parseWdaSource] and consumed by
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
  NativeElement scaled(double factor) =>
      factor == 1 ? this : withBounds(bounds.scaled(factor));

  /// This element with [newBounds].
  NativeElement withBounds(NativeBounds newBounds) => NativeElement(
        className: className,
        clickable: clickable,
        bounds: newBounds,
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
  /// those are not visible.
  bool get isVisible => bounds.width > 0 && bounds.height > 0;

  /// An Android toast. UIAutomator2 adds the toast being shown to the tree
  /// without bounds (seen on API 28; on API 35 the read fails instead), so it
  /// can be read but not acted on.
  bool get isToast => className == 'android.widget.Toast';

  /// Whether reading tools list the element: visible ones and toasts.
  bool get isListed => isVisible || isToast;

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

/// A bootstrap that may reuse a server another process started.
abstract interface class SharedServerBootstrap
    implements NativeServerBootstrap {
  /// Whether [ensureServerReady] started the server, rather than reusing
  /// one that was already running.
  bool get startedServer;
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

  /// Captures a PNG of the full device screen (system dialogs included)
  /// and returns it as a base64-encoded string.
  ///
  /// Unlike the Flutter lane's `take_screenshots`, this captures whatever
  /// is actually on screen — permission dialogs, sheets, status-bar panels —
  /// not just the Flutter view hierarchy.
  Future<String> takeScreenshot();

  /// Current screen size in screenshot pixels and the server-unit scale.
  Future<NativeScreen> getScreen();

  /// Operations on the device that do not use the UI session (the
  /// notification shade).
  NativeDevice get device;

  /// Ends the session and tears down any resources the connector started.
  Future<void> dispose();
}

/// Key under which [parseUiTree] stores each node's tag name in its
/// attribute map, chosen so it cannot collide with real XML attribute names.
const uiNodeTagKey = '#tag';

/// Key under which [parseUiTree] stores the clip of a node's viewport
/// ancestors (see its `viewportOf`).
const uiNodeClipKey = '#clip';

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
///
/// With [viewportOf], a node that it maps to bounds clips its descendants:
/// each relevant node inside one or more such ancestors gets the
/// intersection of their bounds under [uiNodeClipKey] (`x,y,width,height`).
List<Map<String, String>> parseUiTree(
  String xml, {
  required bool Function(Map<String, String> attributes) isRelevant,
  NativeBounds? Function(Map<String, String> attributes)? viewportOf,
}) {
  final nodes = <Map<String, String>>[];
  // Clip in effect inside each open element (null: no viewport ancestor).
  final clips = <NativeBounds?>[];
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
      if (xml.startsWith('</', open) && clips.isNotEmpty) clips.removeLast();
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
    final clip = clips.lastOrNull;
    if (attributes != null && isRelevant(attributes)) {
      nodes.add({
        ...attributes,
        if (clip != null)
          uiNodeClipKey: '${clip.x},${clip.y},${clip.width},${clip.height}',
      });
    }
    if (!tagContent.endsWith('/')) {
      final viewport = attributes == null ? null : viewportOf?.call(attributes);
      clips.add(
        viewport == null
            ? clip
            : clip == null
                ? viewport
                : _intersection(clip, viewport),
      );
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

/// XCUI types that show only the part of their content inside their frame.
const _wdaViewportTypes = {..._wdaScrollableTypes, 'WebView'};

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

  NativeBounds boundsOf(Map<String, String> attributes) => NativeBounds(
        x: _parseWdaInt(attributes['x']),
        y: _parseWdaInt(attributes['y']),
        width: _parseWdaInt(attributes['width']),
        height: _parseWdaInt(attributes['height']),
      );

  final nodes = parseUiTree(
    xml,
    isRelevant: (attributes) {
      if (!attributes[uiNodeTagKey]!.startsWith(_wdaTypePrefix)) return false;
      final name = attributes['name'] ?? '';
      final tag = attributes[uiNodeTagKey]!;
      return isClickable(attributes) ||
          textOf(attributes) != null ||
          name.isNotEmpty ||
          _wdaScrollableTypes.contains(tag.substring(_wdaTypePrefix.length));
    },
    // A scrolled page or list shows only what lies inside its frame; WDA
    // lists the rest with real coordinates.
    viewportOf: (attributes) {
      final tag = attributes[uiNodeTagKey]!;
      if (!tag.startsWith(_wdaTypePrefix) ||
          !_wdaViewportTypes.contains(tag.substring(_wdaTypePrefix.length))) {
        return null;
      }
      final bounds = boundsOf(attributes);
      // A container without size (not laid out yet) clips nothing.
      return bounds.width > 0 && bounds.height > 0 ? bounds : null;
    },
  );

  final elements = nodes.map((attributes) {
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

    final rawClip = attributes[uiNodeClipKey]?.split(',').map(int.parse);
    final clip = rawClip == null
        ? null
        : NativeBounds(
            x: rawClip.elementAt(0),
            y: rawClip.elementAt(1),
            width: rawClip.elementAt(2),
            height: rawClip.elementAt(3),
          );
    final bounds = boundsOf(attributes);

    return NativeElement(
      className: tag,
      text: textOf(attributes),
      resourceId: name.isNotEmpty ? name : null,
      clickable: isClickable(attributes),
      // Outside its viewport the element is hidden: zero size, like
      // Flutter's off-screen nodes, so it is not listed.
      bounds: clip == null ? bounds : _intersection(bounds, clip),
      value: value,
      enabled: attributes['enabled'] != 'false',
      checked: isToggle ? rawValue == '1' : null,
      selected: (attributes['traits'] ?? '').contains('Selected'),
      scrollable: _wdaScrollableTypes.contains(type),
    );
  }).toList();

  // WebDriverAgent also lists elements scrolled out of view — a WebView's
  // whole page with real coordinates below the screen, Flutter's off-screen
  // nodes as 0×0 at (0, 0) — and reports full bounds of partly visible
  // ones. Keep what overlaps the application (the screen) and clip it to
  // the screen, as UIAutomator does, so the center is always a tappable
  // point.
  final screen = elements
      .where((e) => e.className == 'XCUIElementTypeApplication')
      .map((e) => e.bounds)
      .firstOrNull;
  final onScreen = screen == null
      ? elements
      : [
          for (final element in elements)
            if (element.className == 'XCUIElementTypeApplication')
              element
            else if (_overlaps(element.bounds, screen))
              element.withBounds(_clip(element.bounds, screen)),
        ];

  // WDA can list the same element twice (seen with the buttons of the Face
  // ID alert); identical copies would make every selector for it ambiguous.
  final seen = <String>{};
  return [
    for (final element in onScreen)
      if (seen.add(jsonEncode(element.toJson()))) element,
  ];
}

/// WDA emits integer coordinates, but tolerate decimal strings too.
int _parseWdaInt(String? value) {
  if (value == null) return 0;
  return int.tryParse(value) ?? double.tryParse(value)?.round() ?? 0;
}

/// The part of [a] inside [b] (assumes they overlap).
NativeBounds _clip(NativeBounds a, NativeBounds b) {
  final left = max(a.x, b.x);
  final top = max(a.y, b.y);
  final right = min(a.x + a.width, b.x + b.width);
  final bottom = min(a.y + a.height, b.y + b.height);
  return NativeBounds(
    x: left,
    y: top,
    width: right - left,
    height: bottom - top,
  );
}

/// The common part of [a] and [b]; zero-size when they do not overlap.
NativeBounds _intersection(NativeBounds a, NativeBounds b) => _overlaps(a, b)
    ? _clip(a, b)
    : NativeBounds(x: a.x, y: a.y, width: 0, height: 0);

/// Whether [a] and [b] share a non-empty area.
bool _overlaps(NativeBounds a, NativeBounds b) =>
    a.width > 0 &&
    a.height > 0 &&
    b.width > 0 &&
    b.height > 0 &&
    a.x < b.x + b.width &&
    b.x < a.x + a.width &&
    a.y < b.y + b.height &&
    b.y < a.y + a.height;
