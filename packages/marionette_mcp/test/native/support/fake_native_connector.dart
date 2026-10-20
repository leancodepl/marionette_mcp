import 'dart:convert';
import 'dart:math' show min;

import 'package:marionette_mcp/src/native_service/native_connector.dart';

/// Builds a [NativeElement] with sensible defaults for tests.
NativeElement nativeElement({
  String type = 'android.widget.Button',
  String? text,
  String? id,
  bool clickable = true,
  String? value,
  bool enabled = true,
  bool? checked,
  bool scrollable = false,
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
      value: value,
      enabled: enabled,
      checked: checked,
      scrollable: scrollable,
      bounds: NativeBounds(x: x, y: y, width: width, height: height),
    );

/// In-memory [NativeConnector] that records every interaction.
///
/// [screens] is the UI tree sequence: the connector shows `screens[n]` after
/// `n` swipes (the last screen repeats), which models scrolling. Assign
/// [onGetElements] to change the screen over time instead.
class FakeNativeConnector implements NativeConnector {
  FakeNativeConnector({
    List<List<NativeElement>>? screens,
    this.foregroundAppValue = 'com.example.app',
    this.foregroundAppError,
    this.screenshot = 'fake-png-base64',
    this.screen = const NativeScreen(width: 1000, height: 2000, scale: 1),
    this.error,
    FakeNativeDevice? device,
  })  : screens = screens ?? [const []],
        device = device ?? FakeNativeDevice();

  /// Shorthand for a connector with a single, static screen.
  FakeNativeConnector.single(List<NativeElement> elements)
      : this(screens: [elements]);

  final List<List<NativeElement>> screens;

  @override
  final FakeNativeDevice device;

  NativeOrientation orientation = NativeOrientation.portrait;
  String? foregroundAppValue;
  Object? foregroundAppError;
  String screenshot;
  NativeScreen screen;

  /// When set, every UI operation throws it.
  Object? error;

  /// Errors thrown by the next UI operations, one per call, before [error].
  final List<Object> errorsOnce = [];

  /// Errors thrown by the next [enterText] calls only, one per call.
  final List<Object> enterTextErrors = [];

  /// Result of [isServerResponding].
  bool serverResponding = true;
  int healthChecks = 0;

  /// Result of [reopenSession] (null: not supported); [reopenError] makes it
  /// throw instead.
  NativeConnector? reopened;
  Object? reopenError;
  int reopenCalls = 0;

  final List<({int x, int y})> taps = [];
  final List<NativeElement> tappedElements = [];
  final List<({NativeElement element, String text, bool clear})> enteredText =
      [];
  final List<({String text, bool clear})> typedText = [];
  final List<NativeKey> pressedKeys = [];

  /// Result of [isKeyboardShown]; [hideKeyboard] sets it to false.
  bool keyboardShown = false;
  final List<({int startX, int startY, int endX, int endY})> swipes = [];

  /// `holdMs` of each entry in [swipes].
  final List<int> swipeHolds = [];
  final List<({int x, int y, int durationMs})> longPresses = [];
  final List<({int x, int y, int delayMs})> doubleTaps = [];
  final List<({int centerX, int centerY, int startSpan, int endSpan})> pinches =
      [];
  final List<NativeElement> elementScreenshots = [];

  /// When set, replaces [screens]: called with the call count (from 0).
  List<NativeElement> Function(int call)? onGetElements;
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
    final dynamicScreen = onGetElements?.call(getElementsCalls);
    getElementsCalls++;
    return dynamicScreen ?? screens[min(swipes.length, screens.length - 1)];
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
    if (enterTextErrors.isNotEmpty) throw enterTextErrors.removeAt(0);
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
    int holdMs = 0,
  }) async {
    _maybeThrow();
    swipes.add((startX: startX, startY: startY, endX: endX, endY: endY));
    swipeHolds.add(holdMs);
  }

  @override
  Future<void> longPress(int x, int y, {int durationMs = 600}) async {
    _maybeThrow();
    longPresses.add((x: x, y: y, durationMs: durationMs));
  }

  @override
  Future<void> doubleTap(int x, int y, {int delayMs = 100}) async {
    _maybeThrow();
    doubleTaps.add((x: x, y: y, delayMs: delayMs));
  }

  @override
  Future<void> pinch({
    required int centerX,
    required int centerY,
    required int startSpan,
    required int endSpan,
    int durationMs = 500,
  }) async {
    _maybeThrow();
    pinches.add((
      centerX: centerX,
      centerY: centerY,
      startSpan: startSpan,
      endSpan: endSpan,
    ));
  }

  @override
  Future<String> takeElementScreenshot(NativeElement element) async {
    _maybeThrow();
    elementScreenshots.add(element);
    return 'fake-element-png-base64';
  }

  @override
  Future<String> takeScreenshot() async {
    _maybeThrow();
    return screenshot;
  }

  @override
  Future<NativeOrientation> getOrientation() async {
    _maybeThrow();
    return orientation;
  }

  @override
  Future<void> setOrientation(NativeOrientation orientation) async {
    _maybeThrow();
    this.orientation = orientation;
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
  Future<NativeConnector?> reopenSession() async {
    reopenCalls++;
    if (reopenError case final error?) throw error;
    return reopened;
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

/// In-memory [NativeDevice] that records every call.
class FakeNativeDevice implements NativeDevice {
  FakeNativeDevice({
    this.deviceInfo = const NativeDeviceInfo(
      osVersion: 'Android 9',
      apiLevel: 28,
      model: 'Pixel 3',
      isEmulator: true,
      id: 'emulator-5554',
    ),
  });

  NativeDeviceInfo deviceInfo;

  /// Thrown by the next call, when set.
  Object? error;

  /// Result of [setPermission].
  NativePermissionChange permissionChange =
      const NativePermissionChange(nativeNames: ['android.permission.CAMERA']);

  /// Apps reported as running; [activateApp] adds, [terminateApp] removes.
  final Set<String> runningApps = {};

  /// App ids whose process a permission change kills.
  bool permissionChangeKillsApp = false;

  final List<String> calls = [];

  void _record(String call) {
    final pending = error;
    if (pending != null) throw pending;
    calls.add(call);
  }

  @override
  Future<NativeDeviceInfo> info() async {
    _record('info');
    return deviceInfo;
  }

  @override
  Future<NativePermissionChange> setPermission(
    NativePermissionAction action,
    NativePermission permission,
    String appId,
  ) async {
    _record('permission ${action.name} ${permission.name} $appId');
    if (permissionChangeKillsApp) runningApps.remove(appId);
    return permissionChange;
  }

  @override
  Future<void> openUrl(String url) async => _record('openUrl $url');

  @override
  Future<void> activateApp(String appId) async {
    _record('activate $appId');
    runningApps.add(appId);
  }

  @override
  Future<bool> terminateApp(String appId) async {
    _record('terminate $appId');
    return runningApps.remove(appId);
  }

  @override
  Future<bool?> isAppRunning(String appId) async => runningApps.contains(appId);

  @override
  Future<void> openNotifications() async => _record('openNotifications');

  @override
  Future<void> closeNotifications() async => _record('closeNotifications');

  @override
  Future<void> pushNotification(
    String appId,
    Map<String, dynamic> payload,
  ) async =>
      _record('push $appId ${jsonEncode(payload)}');

  @override
  Future<void> setLocation(double latitude, double longitude) async =>
      _record('location $latitude,$longitude');

  @override
  Future<void> biometrics(NativeBiometricAction action) async =>
      _record('biometrics ${action.name}');
}
