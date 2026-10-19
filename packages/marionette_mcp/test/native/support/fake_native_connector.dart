import 'dart:math' show min;

import 'package:marionette_mcp/src/native_service/native_connector.dart';

/// Builds a [NativeElement] with sensible defaults for tests.
NativeElement nativeElement({
  String type = 'android.widget.Button',
  String? text,
  String? id,
  bool clickable = true,
  int x = 0,
  int y = 0,
  int width = 100,
  int height = 50,
}) =>
    NativeElement(
      className: type,
      text: text,
      resourceId: id,
      clickable: clickable,
      bounds: NativeBounds(x: x, y: y, width: width, height: height),
    );

/// In-memory [NativeConnector] that records every interaction.
///
/// [screens] is the UI tree sequence: the connector shows `screens[n]` after
/// `n` swipes (the last screen repeats), which models scrolling.
class FakeNativeConnector implements NativeConnector {
  FakeNativeConnector({
    List<List<NativeElement>>? screens,
    this.foregroundAppValue = 'com.example.app',
    this.foregroundAppError,
    this.screenshot = 'fake-png-base64',
    this.screen = const NativeScreen(width: 1000, height: 2000, scale: 1),
    this.error,
  }) : screens = screens ?? [const []];

  /// Shorthand for a connector with a single, static screen.
  FakeNativeConnector.single(List<NativeElement> elements)
      : this(screens: [elements]);

  final List<List<NativeElement>> screens;
  String? foregroundAppValue;
  Object? foregroundAppError;
  String screenshot;
  NativeScreen screen;

  /// When set, every UI operation throws it.
  Object? error;

  /// Errors thrown by the next UI operations, one per call, before [error].
  final List<Object> errorsOnce = [];

  /// Result of [isServerResponding].
  bool serverResponding = true;
  int healthChecks = 0;

  final List<({int x, int y})> taps = [];
  final List<NativeElement> tappedElements = [];
  final List<({NativeElement element, String text, bool clear})> enteredText =
      [];
  final List<({String text, bool clear})> typedText = [];
  final List<NativeKey> pressedKeys = [];

  /// Result of [isKeyboardShown]; [hideKeyboard] sets it to false.
  bool keyboardShown = false;
  final List<({int startX, int startY, int endX, int endY})> swipes = [];
  int getElementsCalls = 0;
  int disposeCalls = 0;

  void _maybeThrow() {
    if (errorsOnce.isNotEmpty) throw errorsOnce.removeAt(0);
    final pending = error;
    if (pending != null) throw pending;
  }

  @override
  Future<List<NativeElement>> getNativeElements() async {
    _maybeThrow();
    getElementsCalls++;
    return screens[min(swipes.length, screens.length - 1)];
  }

  @override
  Future<String?> get foregroundApp async {
    final pending = foregroundAppError;
    if (pending != null) throw pending;
    return foregroundAppValue;
  }

  @override
  Future<void> tapElement(NativeElement element) async {
    _maybeThrow();
    tappedElements.add(element);
  }

  @override
  Future<void> tapAt(int x, int y) async {
    _maybeThrow();
    taps.add((x: x, y: y));
  }

  @override
  Future<void> enterText(
    NativeElement element,
    String text, {
    bool clear = false,
  }) async {
    _maybeThrow();
    enteredText.add((element: element, text: text, clear: clear));
  }

  @override
  Future<void> typeText(String text, {bool clear = false}) async {
    _maybeThrow();
    typedText.add((text: text, clear: clear));
  }

  @override
  Future<void> pressKey(NativeKey key) async {
    _maybeThrow();
    pressedKeys.add(key);
  }

  @override
  Future<bool> isKeyboardShown() async {
    _maybeThrow();
    return keyboardShown;
  }

  @override
  Future<bool> hideKeyboard() async {
    _maybeThrow();
    final wasShown = keyboardShown;
    keyboardShown = false;
    return wasShown;
  }

  @override
  Future<void> swipe({
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
  }) async {
    _maybeThrow();
    swipes.add((startX: startX, startY: startY, endX: endX, endY: endY));
  }

  @override
  Future<String> takeScreenshot() async {
    _maybeThrow();
    return screenshot;
  }

  @override
  Future<NativeScreen> getScreen() async {
    _maybeThrow();
    return screen;
  }

  @override
  Future<bool> isServerResponding() async {
    healthChecks++;
    return serverResponding;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

/// [NativeServerBootstrap] pointing at an already running server.
class FakeServerBootstrap implements NativeServerBootstrap {
  FakeServerBootstrap(this.baseUrl);

  final String baseUrl;
  int ensureCalls = 0;
  int disposeCalls = 0;

  @override
  Future<Uri> ensureServerReady() async {
    ensureCalls++;
    return Uri.parse(baseUrl);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
