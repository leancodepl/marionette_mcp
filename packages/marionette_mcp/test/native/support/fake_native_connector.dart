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
    this.error,
  }) : screens = screens ?? [const []];

  /// Shorthand for a connector with a single, static screen.
  FakeNativeConnector.single(List<NativeElement> elements)
      : this(screens: [elements]);

  final List<List<NativeElement>> screens;
  String? foregroundAppValue;
  Object? foregroundAppError;
  String screenshot;

  /// When set, every UI operation throws it.
  Object? error;

  final List<({int x, int y})> taps = [];
  final List<NativeElement> tappedElements = [];
  final List<({NativeElement element, String text})> enteredText = [];
  final List<({int startX, int startY, int endX, int endY})> swipes = [];
  int getElementsCalls = 0;
  int disposeCalls = 0;

  void _maybeThrow() {
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
  Future<void> enterText(NativeElement element, String text) async {
    _maybeThrow();
    enteredText.add((element: element, text: text));
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
