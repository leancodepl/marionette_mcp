import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:vm_service/vm_service.dart';

/// Exception thrown when an operation is attempted without an active connection.
class NotConnectedException implements Exception {
  const NotConnectedException();

  @override
  String toString() =>
      'Not connected to any app. Use app.connect tool first with the VM service URI.';
}

/// Exception thrown when a VM service extension call fails.
class VmServiceExtensionException implements Exception {
  VmServiceExtensionException(
    this.message, {
    this.errorCode,
    this.error,
    this.stackTrace,
  });

  /// Creates an exception that preserves the application-side VM extension
  /// details when they are available.
  factory VmServiceExtensionException.fromRpcError(
    String extensionName,
    RPCError rpcError,
  ) {
    final details = rpcError.data?['details'];
    return VmServiceExtensionException(
      'Extension $extensionName failed',
      errorCode: rpcError.code,
      error: details?.toString() ?? rpcError.message,
    );
  }

  final String message;
  final int? errorCode;
  final String? error;
  final String? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write('\nError: $error');
    }
    if (stackTrace != null) {
      buffer.write('\nStack trace: $stackTrace');
    }
    return buffer.toString();
  }
}

/// Builds the wire args for `marionette.interactiveElements`.
///
/// The VM service delivers extension params to the app as a
/// `Map<String, String>`, so [compaction] travels as the name of the
/// `CompactionMode` value rather than as a Dart value the transport would have
/// to coerce — same as the screencast params. An omitted key is what tells the
/// app to use its configured default, so null sends nothing. [ancestorKeys]
/// is JSON-encoded, like on the matcher tools, and omitted when empty.
Map<String, dynamic> interactiveElementsArgs(
  String? compaction, {
  List<String> ancestorKeys = const [],
}) =>
    {
      if (ancestorKeys.isNotEmpty) 'ancestor_keys': jsonEncode(ancestorKeys),
      if (compaction != null) 'compaction': compaction,
    };

/// Modifier keys accepted by [VmServiceConnector.pressKey].
///
/// Must stay in sync with the modifiers the `marionette_flutter`
/// `KeyboardSimulator` understands; this mirror lets the CLI and MCP server
/// (which can't import the Flutter package) reject bad input before it reaches
/// the device.
const supportedKeyModifiers = {'control', 'shift', 'alt', 'meta'};

/// Values accepted for `platformBrightness` by
/// [VmServiceConnector.setDeviceConfig].
///
/// Mirrors Flutter's `Brightness` enum, which the CLI and MCP server can't
/// import, so bad input is rejected before it reaches the device.
const supportedBrightnessValues = {'light', 'dark'};

/// Values accepted for `compaction` by
/// [VmServiceConnector.getInteractiveElements].
///
/// Mirrors the names of the `marionette_flutter` `CompactionMode` enum, which
/// the CLI and MCP server can't import, so bad input is rejected before it
/// reaches the device.
const supportedCompactionModes = {'none', 'compact'};

/// Validates [brightness] against [supportedBrightnessValues].
///
/// Returns a human-readable error message, or `null` when [brightness] is
/// null or supported.
String? invalidBrightnessError(String? brightness) {
  if (brightness == null || supportedBrightnessValues.contains(brightness)) {
    return null;
  }
  return 'Unsupported brightness: $brightness. '
      'Supported values: ${supportedBrightnessValues.join(', ')}.';
}

/// Validates [compaction] against [supportedCompactionModes].
///
/// Returns a human-readable error message, or `null` when [compaction] is
/// null or supported.
String? invalidCompactionError(String? compaction) {
  if (compaction == null || supportedCompactionModes.contains(compaction)) {
    return null;
  }
  return 'Unsupported compaction: $compaction. '
      'Supported values: ${supportedCompactionModes.join(', ')}.';
}

/// Validates a comma-separated [modifiers] string against
/// [supportedKeyModifiers] (case-insensitive).
///
/// Returns a human-readable error message listing the offending entries, or
/// `null` when [modifiers] is null/empty or every entry is supported.
String? invalidModifiersError(String? modifiers) {
  if (modifiers == null || modifiers.trim().isEmpty) return null;
  final invalid = modifiers
      .split(',')
      .map((modifier) => modifier.trim())
      .where((modifier) => modifier.isNotEmpty)
      .where(
          (modifier) => !supportedKeyModifiers.contains(modifier.toLowerCase()))
      .toList();
  if (invalid.isEmpty) return null;
  final plural = invalid.length > 1 ? 's' : '';
  return 'Unsupported modifier$plural: ${invalid.join(', ')}. '
      'Supported modifiers: ${supportedKeyModifiers.join(', ')}.';
}

/// Manages connection to a Flutter app's VM service and provides
/// wrapper methods for custom marionette.* extensions.
class VmServiceConnector {
  VmServiceConnector() : _logger = logging.Logger('VmServiceConnector');

  final logging.Logger _logger;
  VmService? _service;
  String? _isolateId;
  _VmServiceConnection? _connection;

  final Map<String, String?> _registeredServices = {};
  final Map<String, List<Completer<String?>>> _pendingServiceRequests = {};

  /// Returns true if currently connected to a VM service.
  bool get isConnected => _service != null && _isolateId != null;

  /// Connects to a VM service at the given URI.
  ///
  /// Throws an exception if connection fails.
  Future<void> connect(String uri) async {
    final previous = _connection;
    final connection = _VmServiceConnection();
    // Claim ownership before the first await. A newer connect or disconnect
    // supersedes this attempt, including while its HTTP upgrade is pending.
    _connection = connection;
    _service = null;
    _isolateId = null;
    _clearServiceRegistrations();

    _logger.info('Connecting to VM service at $uri');

    try {
      await previous?.dispose();
      _ensureCurrentConnection(connection);
      final socket = await WebSocket.connect(
        uri,
        customClient: connection.client,
      );
      if (!identical(_connection, connection)) {
        await socket.close();
        throw StateError('VM service connection attempt was superseded.');
      }
      // Keep the socket reader independent from VmService's input stream,
      // as vm_service_io does. VmService.dispose cancels its input before
      // closing the socket; canceling the socket reader at that point would
      // prevent the peer's close frame from canceling its keep-alive timer.
      socket.pingInterval = const Duration(seconds: 15);
      final input = StreamController<dynamic>();
      final streamClosed = Completer<void>();
      void closeInput() {
        if (connection.closed) return;
        connection.closed = true;
        // Retain the resource owner for deterministic disconnect/reconnect
        // cleanup, but retire state only if this is still its connection.
        if (identical(_connection, connection)) {
          _service = null;
          _isolateId = null;
          _clearServiceRegistrations();
        }
        if (!streamClosed.isCompleted) streamClosed.complete();
      }

      socket.listen(
        input.add,
        onDone: closeInput,
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning('VM service WebSocket error', error, stackTrace);
          // VmService turns stream closure into disposal and rejects pending
          // RPCs. Its input listener has no onError handler for raw IO errors.
          closeInput();
        },
      );
      final service = VmService(
        input.stream,
        socket.add,
        disposeHandler: socket.close,
        streamClosed: streamClosed.future,
        wsUri: uri,
      );
      connection.service = service;
      _service = service;
      connection.subscription = service.onServiceEvent.listen((e) {
        if (!identical(_connection, connection) || connection.closed) return;
        switch (e.kind) {
          case EventKind.kServiceRegistered:
            final serviceName = e.service!;
            _registeredServices[serviceName] = e.method;
            _logger.info('Service registered: $serviceName -> ${e.method}');
            if (_pendingServiceRequests.containsKey(serviceName)) {
              for (final completer in _pendingServiceRequests[serviceName]!) {
                completer.complete(e.method);
              }
              _pendingServiceRequests.remove(serviceName);
            }
          case EventKind.kServiceUnregistered:
            _registeredServices.remove(e.service!);
            _logger.info('Service unregistered: ${e.service}');
          default:
            _logger.info('Service event: $e');
        }
      });
      try {
        await service
            .streamListen(EventStreams.kService)
            .timeout(const Duration(milliseconds: 500));
      } catch (e) {
        _logger.info('streamListen(EventStreams.kService) skipped: $e');
      }
      _ensureCurrentConnection(connection);

      final isolateId = await _findIsolateWithMarionetteExtensions(
        service,
        connection,
      );
      _ensureCurrentConnection(connection);
      _isolateId = isolateId;
      _logger.info('Connected to isolate: $_isolateId');
    } catch (err) {
      _logger.severe('Failed to connect to VM service', err);
      // A superseded attempt may fail after its replacement has connected.
      // It must only release its own resources, never the new connection.
      if (identical(_connection, connection)) {
        await disconnect();
      } else {
        await connection.dispose();
      }
      rethrow;
    }
  }

  /// Disconnects from the current VM service and cancels any pending connect.
  Future<void> disconnect() async {
    final connection = _connection;
    // Retire ownership synchronously, before disposing asynchronous resources.
    _connection = null;
    _service = null;
    _isolateId = null;
    _clearServiceRegistrations();
    if (connection != null) {
      _logger.info('Disconnecting from VM service');
      await connection.dispose();
      _logger.fine('Disconnected');
    }
  }

  void _ensureCurrentConnection(_VmServiceConnection connection) {
    if (!identical(_connection, connection) || connection.closed) {
      throw StateError('VM service connection was disconnected or superseded.');
    }
  }

  void _clearServiceRegistrations() {
    _registeredServices.clear();
    for (final requests in _pendingServiceRequests.values) {
      for (final completer in requests) {
        completer.complete(null);
      }
    }
    _pendingServiceRequests.clear();
  }

  /// Returns a future that completes with the registered method name for the
  /// given [serviceName].
  ///
  /// If the service is already registered, returns immediately.
  /// Otherwise, waits up to [timeout] for the service to be registered.
  /// Returns `null` if the service is not registered within the timeout.
  Future<String?> waitForServiceRegistration(
    String serviceName, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    if (_registeredServices.containsKey(serviceName)) {
      return _registeredServices[serviceName];
    }

    final completer = Completer<String?>();
    _pendingServiceRequests.putIfAbsent(serviceName, () => []).add(completer);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingServiceRequests[serviceName]?.remove(completer);
        if (_pendingServiceRequests[serviceName]?.isEmpty ?? false) {
          _pendingServiceRequests.remove(serviceName);
        }
        return null;
      },
    );
  }

  /// Ensures that there is an active connection.
  ///
  /// Throws [NotConnectedException] if not connected.
  void _ensureConnected() {
    if (!isConnected) {
      throw const NotConnectedException();
    }
  }

  /// Calls a marionette VM service extension and handles the response.
  ///
  /// This is an internal method used by the typed wrapper methods
  /// (e.g., [tap], [getInteractiveElements]).
  Future<Map<String, dynamic>> _callExtension(
    String extensionName,
    Map<String, dynamic> args,
  ) async {
    _ensureConnected();

    _logger.fine('Calling extension: $extensionName with args: $args');

    try {
      final response = await _service!.callServiceExtension(
        'ext.flutter.$extensionName',
        isolateId: _isolateId,
        args: args,
      );

      final responseJson = response.json;
      if (responseJson == null) {
        throw VmServiceExtensionException(
          'Extension $extensionName returned null response',
        );
      }

      _logger.finest('Extension response: $responseJson');

      return responseJson;
    } on RPCError catch (e, stackTrace) {
      _logger.severe('Error calling extension $extensionName', e, stackTrace);
      throw VmServiceExtensionException.fromRpcError(extensionName, e);
    } catch (err) {
      _logger.severe('Error calling extension $extensionName', err);
      rethrow;
    }
  }

  /// Gets the version of the marionette_flutter binding.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<String> getVersion() async {
    final response = await _callExtension('marionette.getVersion', {});
    return response['version'] as String;
  }

  /// Whether the app opted into session reports via
  /// `MarionetteConfiguration.enableSessionReports`.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<bool> getSessionReportsEnabled() async {
    final response = await _callExtension('marionette.getConfiguration', {});
    return response['enableSessionReports'] == true;
  }

  /// Calls a custom VM service extension registered by the Flutter app.
  ///
  /// This is an escape hatch for calling app-specific extensions that are
  /// not part of marionette's built-in tools. For marionette extensions,
  /// use the dedicated methods (e.g., [tap], [getInteractiveElements]).
  ///
  /// [extensionName] should not include the `ext.flutter.` prefix as it
  /// is added automatically.
  ///
  /// Throws [ArgumentError] if [extensionName] is empty or already
  /// contains the `ext.flutter.` prefix.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> callCustomExtension(
    String extensionName, [
    Map<String, dynamic> args = const {},
  ]) {
    if (extensionName.isEmpty) {
      throw ArgumentError.value(
        extensionName,
        'extensionName',
        'must not be empty',
      );
    }
    if (extensionName.startsWith('ext.flutter.')) {
      throw ArgumentError.value(
        extensionName,
        'extensionName',
        'must not include the "ext.flutter." prefix, it is added automatically',
      );
    }
    return _callExtension(extensionName, args);
  }

  /// Gets the list of custom extensions registered by the Flutter app.
  ///
  /// Returns extensions registered via `registerMarionetteExtension` in the
  /// Flutter app. Each extension includes its name and optional description.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> listExtensions() {
    return _callExtension('marionette.listExtensions', {});
  }

  /// Gets the list of interactive elements in the widget tree.
  ///
  /// When [ancestorKeys] is given, only the subtree it names is listed. The
  /// keys nest, outermost first, and the call fails if any of them matches no
  /// element.
  ///
  /// [compaction] must be one of [supportedCompactionModes]. It overrides the
  /// app's `MarionetteConfiguration.compaction` default in both directions;
  /// pass null to use it (see `get_interactive_elements`).
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> getInteractiveElements({
    List<String> ancestorKeys = const [],
    String? compaction,
  }) {
    return _callExtension(
      'marionette.interactiveElements',
      interactiveElementsArgs(compaction, ancestorKeys: ancestorKeys),
    );
  }

  /// Taps an element matching the given criteria.
  ///
  /// [matcher] should contain one of:
  /// - 'key': matches by `ValueKey<String>`
  /// - 'text': matches by visible text content
  /// - 'type': matches by widget type name
  /// - 'x' and 'y': screen coordinates for tapping at a specific position
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> tap(Map<String, dynamic> matcher) {
    return _callExtension('marionette.tap', matcher);
  }

  /// Secondary-taps (right mouse button) an element matching the given
  /// criteria. Desktop only — dispatches a mouse pointer with the secondary
  /// button pressed.
  ///
  /// [matcher] should contain one of: 'key', 'text', 'type', or 'x' & 'y'.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> secondaryTap(Map<String, dynamic> matcher) {
    return _callExtension('marionette.secondaryTap', matcher);
  }

  /// Double taps an element matching the given criteria.
  ///
  /// [matcher] should contain one of:
  /// - 'key': matches by `ValueKey<String>`
  /// - 'text': matches by visible text content
  /// - 'type': matches by widget type name
  /// - 'x' and 'y': screen coordinates
  ///
  /// [delayMs] is the delay between taps in milliseconds (default: 100).
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> doubleTap(
    Map<String, dynamic> matcher, {
    int? delayMs,
  }) {
    final args = Map<String, dynamic>.from(matcher);
    if (delayMs != null) {
      args['delay'] = delayMs;
    }
    return _callExtension('marionette.doubleTap', args);
  }

  /// Long presses an element matching the given criteria.
  ///
  /// [matcher] should contain one of:
  /// - 'key': matches by `ValueKey<String>`
  /// - 'text': matches by visible text content
  /// - 'type': matches by widget type name
  /// - 'x' and 'y': screen coordinates
  ///
  /// [durationMs] is the hold duration in milliseconds (default: 600).
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> longPress(
    Map<String, dynamic> matcher, {
    int? durationMs,
  }) {
    final args = Map<String, dynamic>.from(matcher);
    if (durationMs != null) {
      args['duration'] = durationMs;
    }
    return _callExtension('marionette.longPress', args);
  }

  /// Enters text into a text field matching the given criteria.
  ///
  /// [matcher] should contain either 'key' or 'text' field.
  /// [input] is the text to enter.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> enterText(
    Map<String, dynamic> matcher,
    String input,
  ) {
    final args = Map<String, dynamic>.from(matcher)..['input'] = input;
    return _callExtension('marionette.enterText', args);
  }

  /// Presses a keyboard key against the currently focused element.
  ///
  /// [key] is a named key (e.g. 'enter', 'tab', 'escape', 'backspace',
  /// 'arrowDown') or a single character ('a'-'z', '0'-'9').
  /// [modifiers] is an optional comma-separated list of modifiers to hold
  /// during the press: any of 'control', 'shift', 'alt', 'meta'.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> pressKey(
    String key, {
    String? modifiers,
  }) {
    final error = invalidModifiersError(modifiers);
    if (error != null) {
      throw ArgumentError(error);
    }
    final args = <String, dynamic>{'key': key};
    // Only forward modifiers when there is real content; a blank/whitespace
    // string means "no modifiers" (matching invalidModifiersError) and should
    // not be sent over the wire.
    if (modifiers != null && modifiers.trim().isNotEmpty) {
      args['modifiers'] = modifiers;
    }
    return _callExtension('marionette.pressKey', args);
  }

  /// Simulates a swipe gesture.
  ///
  /// Supports two modes:
  /// - Coordinate-based: [args] should contain 'startX', 'startY', 'endX', 'endY'
  /// - Element-based: [args] should contain a matcher ('key' or 'text'),
  ///   'direction' ('left', 'right', 'up', 'down'), and optional 'distance'
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> swipe(Map<String, dynamic> args) {
    return _callExtension('marionette.swipe', args);
  }

  /// Simulates a pinch zoom gesture on an element matching the given criteria.
  ///
  /// [matcher] should contain a matching field (key, text, type, or x/y).
  /// [scale] controls zoom: > 1.0 zooms in, < 1.0 zooms out.
  /// [startDistance] is the initial finger distance in pixels.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> pinchZoom(
    Map<String, dynamic> matcher, {
    required double scale,
    double? startDistance,
  }) {
    final args = Map<String, dynamic>.from(matcher);
    args['scale'] = scale;
    if (startDistance != null) {
      args['startDistance'] = startDistance;
    }
    return _callExtension('marionette.pinchZoom', args);
  }

  /// Simulates a system back button press.
  ///
  /// Returns the response including whether a route was popped.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> pressBackButton() {
    return _callExtension('marionette.pressBackButton', {});
  }

  /// Scrolls until an element matching the given criteria is visible.
  ///
  /// [matcher] should contain either 'key' or 'text' field.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> scrollToElement(Map<String, dynamic> matcher) {
    return _callExtension('marionette.scrollTo', matcher);
  }

  /// Overrides the device configuration the app sees through `MediaQuery`.
  ///
  /// Omitted fields keep whatever was set before. [reset] clears every
  /// override first, so passing it alone reverts to the platform defaults and
  /// passing it alongside values leaves exactly those values set.
  ///
  /// [platformBrightness] must be one of [supportedBrightnessValues].
  ///
  /// Requires the app to have mounted a `MarionetteDeviceConfig` widget;
  /// without one the extension answers with setup instructions instead of
  /// applying anything.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> setDeviceConfig({
    double? textScale,
    bool? boldText,
    String? platformBrightness,
    bool reset = false,
  }) {
    return _callExtension('marionette.setDeviceConfig', {
      if (textScale != null) 'textScale': textScale,
      if (boldText != null) 'boldText': boldText,
      if (platformBrightness != null) 'platformBrightness': platformBrightness,
      if (reset) 'reset': true,
    });
  }

  /// Gets the collected application logs.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> getLogs() {
    return _callExtension('marionette.getLogs', {});
  }

  /// Takes screenshots of all views in the app.
  ///
  /// Returns a list of base64-encoded PNG images.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> takeScreenshots() {
    return _callExtension('marionette.takeScreenshots', {});
  }

  /// Starts the screencast on the connected Flutter app.
  ///
  /// Returns viewport dimensions that can be used to configure video encoding.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) {
    return _callExtension('marionette.startScreencast', {
      if (maxWidth != null) 'maxWidth': maxWidth.toString(),
      if (maxHeight != null) 'maxHeight': maxHeight.toString(),
      if (wsPort != null) 'wsPort': wsPort.toString(),
    });
  }

  /// Stops the screencast on the connected Flutter app.
  ///
  /// Idempotent — safe to call even if screencast is not running.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> stopScreencast() {
    return _callExtension('marionette.stopScreencast', {});
  }

  /// Performs a hot reload of the Flutter app.
  ///
  /// Returns information about the reload result.
  /// Throws [NotConnectedException] if not connected.
  Future<bool> hotReload() async {
    _ensureConnected();

    final connection = _connection!;
    final service = _service!;
    final isolateId = _isolateId!;
    _logger.info('Performing hot reload');

    try {
      final method = await waitForServiceRegistration('reloadSources');
      _ensureCurrentConnection(connection);
      if (method == null) {
        final report = await service.reloadSources(isolateId);
        _logger.fine('Hot reload completed: success=${report.success}');
        return report.success ?? false;
      } else {
        final result = await service.callMethod(
          method,
          isolateId: isolateId,
        );
        _logger.fine('Hot reload completed: result=${result.json}');
        return result.json?['type'] == 'Success';
      }
    } catch (err) {
      _logger.severe('Hot reload failed', err);
      rethrow;
    }
  }

  /// Performs a hot restart of the Flutter app.
  ///
  /// Unlike [hotReload], a hot restart fully restarts the app from `main()`
  /// and resets all state. There is no native VM service RPC for this — it
  /// relies on the `hotRestart` service that `flutter run` registers over the
  /// VM service. Returns `false` if that service is not available (e.g. the
  /// app was not launched via `flutter run`).
  ///
  /// On success the root isolate is replaced, so the cached isolate id is
  /// re-resolved to the freshly started isolate before returning.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<bool> hotRestart() async {
    _ensureConnected();

    final connection = _connection!;
    final service = _service!;
    final isolateId = _isolateId!;
    _logger.info('Performing hot restart');

    try {
      final method = await waitForServiceRegistration('hotRestart');
      _ensureCurrentConnection(connection);
      if (method == null) {
        _logger.warning(
          'hotRestart service not registered; app must be run via flutter run',
        );
        return false;
      }

      final result = await service.callMethod(method, isolateId: isolateId);
      _ensureCurrentConnection(connection);
      _logger.fine('Hot restart completed: result=${result.json}');
      final success = result.json?['type'] == 'Success';

      if (success) {
        // The previous isolate was torn down and replaced. Re-resolve the new
        // isolate, retrying while it boots and re-registers its extensions.
        final replacementIsolateId = await _findIsolateWithMarionetteExtensions(
          service,
          connection,
          attempts: 10,
          delay: const Duration(milliseconds: 500),
        );
        _ensureCurrentConnection(connection);
        _isolateId = replacementIsolateId;
        _logger.info('Reconnected to isolate after hot restart: $_isolateId');
      }

      return success;
    } catch (err) {
      _logger.severe('Hot restart failed', err);
      rethrow;
    }
  }

  /// Finds the first isolate that has the marionette extensions.
  ///
  /// After a hot restart the root isolate is replaced and registers its
  /// extensions asynchronously, so this polls up to [attempts] times with a
  /// [delay] between tries before giving up.
  ///
  /// Throws an exception if no suitable isolate is found within the retries.
  Future<String> _findIsolateWithMarionetteExtensions(
    VmService service,
    _VmServiceConnection connection, {
    int attempts = 1,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(delay);
      }

      _ensureCurrentConnection(connection);
      final vm = await service.getVM();
      _ensureCurrentConnection(connection);
      if (vm.isolates == null || vm.isolates!.isEmpty) {
        continue;
      }

      // Find the first isolate that has the marionette.getLogs extension
      for (final isolateRef in vm.isolates!) {
        if (isolateRef.id == null) {
          continue;
        }

        try {
          final isolate = await service.getIsolate(isolateRef.id!);
          _ensureCurrentConnection(connection);
          final hasExtension = isolate.extensionRPCs?.any(
                (ext) => ext == 'ext.flutter.marionette.getLogs',
              ) ??
              false;

          if (hasExtension) {
            return isolateRef.id!;
          }
        } catch (err) {
          _ensureCurrentConnection(connection);
          _logger.warning(
            'Failed to check extensions for isolate ${isolateRef.id}',
            err,
          );
          continue;
        }
      }
    }

    throw Exception(
      'No isolate found with ext.flutter.marionette.getLogs extension. '
      'Make sure the Flutter app has marionette_flutter initialized.',
    );
  }
}

/// Resources owned by one connection attempt, including its pending upgrade.
class _VmServiceConnection {
  final HttpClient client = HttpClient();
  VmService? service;
  StreamSubscription<Event>? subscription;
  bool closed = false;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    // Force-close the HTTP request even if no WebSocket/VmService exists yet.
    client.close(force: true);
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    await subscription?.cancel();
    await service?.dispose();
  }
}
