/// Core types for the native automation lane.
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
/// Produced by platform parsers under `parsing/` and consumed by
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

  /// Android `resource-id`, iOS accessibility identifier (`name`), or HTML
  /// element `id`, if any.
  final String? resourceId;

  /// Native class of the element (e.g. `android.widget.Button`,
  /// `XCUIElementTypeButton`, HTML tag name).
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
/// WebDriverAgent on iOS, ChromeDriver on web).
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

  /// Captures a PNG of the full device screen and returns base64 payload.
  Future<String> takeScreenshot();

  /// Ends the session and tears down any resources the connector started.
  Future<void> dispose();
}
