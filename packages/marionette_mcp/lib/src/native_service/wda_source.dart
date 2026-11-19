import 'dart:convert' show jsonEncode;

import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/ui_tree.dart';

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

/// Prefix of every XCUI element type WDA reports (`XCUIElementTypeButton`).
const _wdaTypePrefix = 'XCUIElementType';

/// The XCUI type [tag] names without [_wdaTypePrefix] (`Button`), or null when
/// [tag] is not an XCUI element type.
String? wdaType(String tag) => tag.startsWith(_wdaTypePrefix)
    ? tag.substring(_wdaTypePrefix.length)
    : null;

/// XCUI types whose `value` is an on/off state (`"1"` / `"0"`).
const _wdaToggleTypes = {'Switch', 'CheckBox', 'Toggle'};

/// XCUI text-entry types.
const _wdaEditableTypes = {
  'TextField',
  'SecureTextField',
  'TextView',
  'SearchField',
};

/// Whether the XCUI element type [className] is a text field.
bool isWdaEditableClass(String className) =>
    _wdaEditableTypes.contains(wdaType(className));

/// XCUI types whose `value` is user content worth reporting.
const _wdaValueTypes = {..._wdaEditableTypes, 'Slider'};

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
/// Filtering matches `parseAndroidUiDump`: clickable, or non-empty text, or
/// non-empty identifier.
List<NativeElement> parseWdaSource(String xml) {
  bool isClickable(Map<String, String> attributes) =>
      attributes['enabled'] == 'true' &&
      _wdaInteractiveTypes.contains(wdaType(attributes[uiNodeTagKey]!));

  // A field is named by its label, else its placeholder; its content is
  // reported as `value` (see below), so typing does not rename it.
  String? textOf(Map<String, String> attributes) {
    final keys = isWdaEditableClass(attributes[uiNodeTagKey]!)
        ? const ['label', 'placeholderValue', 'value']
        : const ['label', 'value'];
    for (final key in keys) {
      final text = attributes[key] ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  final nodes = parseUiTree(
    xml,
    adjust: _toScreenFrame,
    isRelevant: (attributes) {
      final type = wdaType(attributes[uiNodeTagKey]!);
      if (type == null) return false;
      final name = attributes['name'] ?? '';
      return isClickable(attributes) ||
          textOf(attributes) != null ||
          name.isNotEmpty ||
          _wdaScrollableTypes.contains(type);
    },
    // A scrolled page or list shows only what lies inside its frame; WDA
    // lists the rest with real coordinates.
    viewportOf: (attributes) {
      if (!_wdaViewportTypes.contains(wdaType(attributes[uiNodeTagKey]!))) {
        return null;
      }
      final bounds = _wdaFrame(attributes);
      // A container without size (not laid out yet) clips nothing.
      return bounds.width > 0 && bounds.height > 0 ? bounds : null;
    },
  );

  final elements = nodes.map((node) {
    final (:attributes, :clip) = node;
    final name = attributes['name'] ?? '';
    final tag = attributes[uiNodeTagKey]!;
    final type = wdaType(tag);
    final rawValue = attributes['value'] ?? '';
    final isToggle = _wdaToggleTypes.contains(type);
    // Other types use `value` for unrelated state (a selected tab button
    // reports "1"), and an empty field reports its placeholder as `value`.
    final value = _wdaValueTypes.contains(type) &&
            rawValue.isNotEmpty &&
            rawValue != attributes['placeholderValue']
        ? rawValue
        : null;

    final bounds = _wdaFrame(attributes);

    return NativeElement(
      className: tag,
      text: textOf(attributes),
      resourceId: name.isNotEmpty ? name : null,
      clickable: isClickable(attributes),
      // Outside its viewport the element is hidden: zero size, like
      // Flutter's off-screen nodes, so it is not listed.
      bounds: clip == null ? bounds : bounds.intersection(clip),
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
            else if (element.bounds.overlaps(screen))
              element.withBounds(element.bounds.intersection(screen)),
        ];

  // WDA can list the same element twice (seen with the buttons of the Face
  // ID alert); identical copies would make every selector for it ambiguous.
  final seen = <String>{};
  return [
    for (final element in onScreen)
      if (seen.add(jsonEncode(element.toJson()))) element,
  ];
}

/// Whether WDA page source [xml] contains a keyboard that is on screen.
///
/// A hidden keyboard can stay in the tree, parked just below the screen
/// (`y` equal to the application height, `visible="false"`) — e.g. when
/// it was dismissed while the field kept focus. Mere presence would report
/// it as shown and make `hideKeyboard` fail. The keyboard counts as shown
/// when it has a size and its top edge is above the bottom of the
/// application (the screen). Missing geometry is treated as shown.
/// `visible` alone is not used: WDA reports it inconsistently (tabs covered
/// by the keyboard are `visible="false"` while on screen).
bool wdaKeyboardOnScreen(String xml) {
  final nodes = parseUiTree(
    xml,
    isRelevant: (attributes) {
      final tag = attributes[uiNodeTagKey];
      return tag == 'XCUIElementTypeKeyboard' ||
          tag == 'XCUIElementTypeApplication';
    },
  ).map((node) => node.attributes);
  final screenHeight = nodes
      .where((n) => n[uiNodeTagKey] == 'XCUIElementTypeApplication')
      .map((n) => double.tryParse(n['height'] ?? ''))
      .firstOrNull;
  return nodes
      .where((n) => n[uiNodeTagKey] == 'XCUIElementTypeKeyboard')
      .any((keyboard) {
    final y = double.tryParse(keyboard['y'] ?? '');
    final height = double.tryParse(keyboard['height'] ?? '');
    if (y == null || height == null || screenHeight == null) return true;
    return height > 0 && y < screenHeight;
  });
}

/// Reads a bundle identifier from WDA page source when
/// `WebDriverClient.wdaActiveAppInfo` is unavailable.
String? foregroundAppFromWdaSource(String xml) {
  final apps = parseUiTree(
    xml,
    isRelevant: (attributes) =>
        attributes[uiNodeTagKey] == 'XCUIElementTypeApplication',
  );
  if (apps.isEmpty) return null;

  final attrs = apps.first.attributes;
  final bundleId = attrs['bundleId'] ?? '';
  if (bundleId.isNotEmpty) return bundleId;

  final name = attrs['name'] ?? '';
  if (_bundleIdentifierPattern.hasMatch(name)) return name;

  return null;
}

final _bundleIdentifierPattern = RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$');

/// Offset that turns a node's frame into screen coordinates, inherited by
/// its descendants (see [_toScreenFrame]).
const _wdaOffsetXKey = '#dx';
const _wdaOffsetYKey = '#dy';

/// Rewrites a WDA node's `x`/`y` to screen coordinates.
///
/// A view served by another process (the share sheet's
/// `ShareSheet.RemoteContainerView`, seen on iOS 26.4) reports its
/// descendants' frames relative to itself: its content starts at (0, 0)
/// with the container's size, though the container is elsewhere on screen.
/// From there on, the subtree is moved by the container's origin. A WebView
/// has nodes of the same shape, but below them frames are on screen again:
/// a node whose own frame lies within its parent's ends the move for its
/// subtree. Content merely scrolled out of its container keeps its frame.
Map<String, String> _toScreenFrame(
  Map<String, String> attributes,
  Map<String, String>? parent,
) {
  if (parent == null || !attributes.containsKey('x')) return attributes;
  var dx = _parseWdaInt(parent[_wdaOffsetXKey]);
  var dy = _parseWdaInt(parent[_wdaOffsetYKey]);
  final raw = _wdaFrame(attributes);
  final parentFrame = _wdaFrame(parent);
  final sized = raw.width > 0 && raw.height > 0;
  if (sized &&
      raw.x == 0 &&
      raw.y == 0 &&
      (parentFrame.x != 0 || parentFrame.y != 0) &&
      (raw.width - parentFrame.width).abs() <= 1 &&
      (raw.height - parentFrame.height).abs() <= 1) {
    dx = parentFrame.x;
    dy = parentFrame.y;
  } else if ((dx != 0 || dy != 0) && sized && _contains(parentFrame, raw)) {
    dx = 0;
    dy = 0;
  }
  if (dx == 0 && dy == 0) return attributes;
  final frame = _wdaFrame(attributes, dx: dx, dy: dy);
  return {
    ...attributes,
    'x': '${frame.x}',
    'y': '${frame.y}',
    _wdaOffsetXKey: '$dx',
    _wdaOffsetYKey: '$dy',
  };
}

/// The frame in a WDA node's attributes, moved by ([dx], [dy]).
NativeBounds _wdaFrame(
  Map<String, String> attributes, {
  int dx = 0,
  int dy = 0,
}) =>
    NativeBounds(
      x: _parseWdaInt(attributes['x']) + dx,
      y: _parseWdaInt(attributes['y']) + dy,
      width: _parseWdaInt(attributes['width']),
      height: _parseWdaInt(attributes['height']),
    );

/// Whether [inner] lies within [outer], allowing a point of rounding.
bool _contains(NativeBounds outer, NativeBounds inner) =>
    inner.x >= outer.x - 1 &&
    inner.y >= outer.y - 1 &&
    inner.x + inner.width <= outer.x + outer.width + 1 &&
    inner.y + inner.height <= outer.y + outer.height + 1;

/// WDA emits integer coordinates, but tolerate decimal strings too.
int _parseWdaInt(String? value) {
  if (value == null) return 0;
  return int.tryParse(value) ?? double.tryParse(value)?.round() ?? 0;
}
