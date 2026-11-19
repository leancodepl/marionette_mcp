/// Native automation lane: connector interface and element model shared by
/// Android (UIAutomator2) and iOS (WebDriverAgent) implementations.
library;

import 'dart:math' show max, min;

import 'package:marionette_mcp/src/native_service/native_device.dart';
import 'package:marionette_mcp/src/native_service/native_key.dart';

export 'package:marionette_mcp/src/native_service/native_device.dart';
export 'package:marionette_mcp/src/native_service/native_key.dart';

/// Rectangle in **screen pixels**: the device screen's own pixels, on every
/// platform. `native_take_screenshot` may return a smaller image and then
/// reports the factor between the two.
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

  /// Whether the point ([x], [y]) lies within these bounds.
  bool contains(int x, int y) =>
      x >= this.x && x < this.x + width && y >= this.y && y < this.y + height;

  /// Whether these bounds and [other] share a non-empty area.
  bool overlaps(NativeBounds other) =>
      width > 0 &&
      height > 0 &&
      other.width > 0 &&
      other.height > 0 &&
      x < other.x + other.width &&
      other.x < x + width &&
      y < other.y + other.height &&
      other.y < y + height;

  /// The common part of these bounds and [other]; zero-size at this origin
  /// when they do not overlap.
  NativeBounds intersection(NativeBounds other) {
    if (!overlaps(other)) return NativeBounds(x: x, y: y, width: 0, height: 0);
    final left = max(x, other.x);
    final top = max(y, other.y);
    final right = min(x + width, other.x + other.width);
    final bottom = min(y + height, other.y + other.height);
    return NativeBounds(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }

  /// These bounds multiplied by [factor], rounded to whole pixels.
  NativeBounds scaled(double factor) {
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

/// Size of the device screen in screen pixels, plus how many
/// screen pixels make up one server unit ([scale]; 1 on Android, the
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

  /// The whole screen as bounds.
  NativeBounds get bounds =>
      NativeBounds(x: 0, y: 0, width: width, height: height);

  Map<String, Object> toJson() => {
        'width': width,
        'height': height,
        'scale': scale,
      };
}

/// A single element of the native UI hierarchy.
///
/// Produced by `parseAndroidUiDump` / `parseWdaSource` and consumed by
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

  /// On-screen rectangle in screen pixels.
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

  /// Center of [bounds] in screen pixels — the natural tap target.
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

  /// Stops whatever [ensureServerReady] started. A step that fails is logged
  /// and the rest goes on.
  Future<void> dispose();
}

/// A bootstrap that may reuse a server another process started.
abstract interface class SharedServerBootstrap
    implements NativeServerBootstrap {
  /// Whether [ensureServerReady] started the server, rather than reusing
  /// one that was already running.
  bool get startedServer;
}

/// Delay before a field is looked up again when it changed or did not take
/// the focus before anything was typed.
const changedFieldRetryDelay = Duration(milliseconds: 300);

/// A connected native automation session (UIAutomator2 on Android,
/// WebDriverAgent on iOS).
///
/// Implementations own the underlying WebDriver session and any device-side
/// processes; [dispose] must release both. All coordinates, in and out, are
/// screen pixels (see [NativeBounds]).
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

  /// Taps at ([x], [y]) in screen pixels.
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

  /// Swipes from ([startX], [startY]) to ([endX], [endY]) in screen pixels
  /// over [durationMs] milliseconds.
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

  /// Current screen size in screen pixels and the server-unit scale.
  Future<NativeScreen> getScreen();

  /// Operations on the device: the notification shade.
  NativeDevice get device;

  /// Ends the session and tears down any resources the connector started.
  Future<void> dispose();
}
