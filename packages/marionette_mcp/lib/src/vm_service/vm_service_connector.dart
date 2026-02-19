import 'dart:async';

import 'package:logging/logging.dart' as logging;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

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

/// Manages connection to a Flutter app's VM service and provides
/// wrapper methods for custom marionette.* extensions.
class VmServiceConnector {
  VmServiceConnector() : _logger = logging.Logger('VmServiceConnector');

  final logging.Logger _logger;
  VmService? _service;
  String? _isolateId;
  StreamSubscription<Event>? _serviceEventSubscription;

  final Map<String, String?> _registeredServices = {};
  final Map<String, List<Completer<String?>>> _pendingServiceRequests = {};

  /// Returns true if currently connected to a VM service.
  bool get isConnected => _service != null && _isolateId != null;

  /// Connects to a VM service at the given URI.
  ///
  /// Throws an exception if connection fails.
  Future<void> connect(String uri) async {
    if (isConnected) {
      _logger.warning('Already connected, disconnecting first');
      await disconnect();
    }

    _logger.info('Connecting to VM service at $uri');

    try {
      _service = await vmServiceConnectUri(uri);
      _serviceEventSubscription = _service!.onServiceEvent.listen((e) {
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
      await _service!.streamListen(EventStreams.kService);

      _isolateId = await _findIsolateWithMarionetteExtensions();
      _logger.info('Connected to isolate: $_isolateId');
    } catch (err) {
      _service = null;
      _isolateId = null;
      _logger.severe('Failed to connect to VM service', err);
      rethrow;
    }
  }

  /// Disconnects from the current VM service.
  Future<void> disconnect() async {
    if (_service != null) {
      _logger.info('Disconnecting from VM service');
      await _serviceEventSubscription?.cancel();
      _serviceEventSubscription = null;
      await _service!.dispose();
      _service = null;
      _isolateId = null;
      _registeredServices.clear();
      _pendingServiceRequests.clear();
      _logger.fine('Disconnected');
    }
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
    } on RPCError catch (e) {
      _logger.severe('Error calling extension $extensionName', e);
      throw VmServiceExtensionException(
        'Extension $extensionName failed',
        errorCode: e.code,
        error: e.message,
      );
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
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> getInteractiveElements() {
    return _callExtension('marionette.interactiveElements', {});
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

  /// Scrolls until an element matching the given criteria is visible.
  ///
  /// [matcher] should contain either 'key' or 'text' field.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> scrollToElement(Map<String, dynamic> matcher) {
    return _callExtension('marionette.scrollTo', matcher);
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

  /// Performs a hot reload of the Flutter app.
  ///
  /// Returns information about the reload result.
  /// Throws [NotConnectedException] if not connected.
  Future<bool> hotReload() async {
    _ensureConnected();

    _logger.info('Performing hot reload');

    try {
      final method = await waitForServiceRegistration('reloadSources');
      if (method == null) {
        final report = await _service!.reloadSources(_isolateId!);
        _logger.fine('Hot reload completed: success=${report.success}');
        return report.success ?? false;
      } else {
        final result = await _service!.callMethod(
          method,
          isolateId: _isolateId!,
        );
        _logger.fine('Hot reload completed: result=${result.json}');
        return result.json?['type'] == 'Success';
      }
    } catch (err) {
      _logger.severe('Hot reload failed', err);
      rethrow;
    }
  }

  /// Finds the first isolate that has the marionette extensions.
  ///
  /// Throws an exception if no suitable isolate is found.
  Future<String> _findIsolateWithMarionetteExtensions() async {
    final vm = await _service!.getVM();
    if (vm.isolates == null || vm.isolates!.isEmpty) {
      throw Exception('No isolates found in the VM');
    }

    // Find the first isolate that has the marionette.getLogs extension
    for (final isolateRef in vm.isolates!) {
      if (isolateRef.id == null) {
        continue;
      }

      try {
        final isolate = await _service!.getIsolate(isolateRef.id!);
        final hasExtension =
            isolate.extensionRPCs?.any(
              (ext) => ext == 'ext.flutter.marionette.getLogs',
            ) ??
            false;

        if (hasExtension) {
          return isolateRef.id!;
        }
      } catch (err) {
        _logger.warning(
          'Failed to check extensions for isolate ${isolateRef.id}',
          err,
        );
        continue;
      }
    }

    throw Exception(
      'No isolate found with ext.flutter.marionette.getLogs extension. '
      'Make sure the Flutter app has marionette_flutter initialized.',
    );
  }
}
