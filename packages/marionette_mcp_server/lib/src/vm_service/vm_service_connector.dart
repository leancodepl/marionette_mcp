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
  VmServiceExtensionException(this.message, this.error, this.stackTrace);

  final String message;
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
      _logger.fine('Connected to VM service');

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
      await _service!.dispose();
      _service = null;
      _isolateId = null;
      _logger.fine('Disconnected');
    }
  }

  /// Ensures that there is an active connection.
  ///
  /// Throws [NotConnectedException] if not connected.
  void _ensureConnected() {
    if (!isConnected) {
      throw const NotConnectedException();
    }
  }

  /// Calls a VM service extension and handles the response.
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
          null,
          null,
        );
      }

      _logger.finest('Extension response: $responseJson');

      // Check if the response indicates an error
      if (responseJson['type'] == 'Error') {
        throw VmServiceExtensionException(
          'Extension $extensionName failed',
          responseJson['error'] as String?,
          responseJson['stackTrace'] as String?,
        );
      }

      return responseJson;
    } catch (err) {
      _logger.severe('Error calling extension $extensionName', err);
      rethrow;
    }
  }

  /// Gets the list of interactive elements in the widget tree.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> getInteractiveElements() {
    return _callExtension('marionette.interactiveElements', {});
  }

  /// Taps an element matching the given criteria.
  ///
  /// [matcher] should contain either 'key' or 'text' field.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> tapElement(
    Map<String, dynamic> matcher,
  ) {
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
  Future<Map<String, dynamic>> scrollToElement(
    Map<String, dynamic> matcher,
  ) {
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
        final hasExtension = isolate.extensionRPCs
                ?.any((ext) => ext == 'ext.flutter.marionette.getLogs') ??
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
