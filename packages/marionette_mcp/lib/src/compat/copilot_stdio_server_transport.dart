import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';

/// A stdio transport that applies small compatibility fixes for MCP clients.
///
/// Why this exists:
/// Some clients (notably GitHub Copilot) send `initialize.capabilities.tasks.list`
/// and `initialize.capabilities.tasks.cancel` as objects (`{}`) instead of booleans.
/// `mcp_dart` 1.2.1 expects booleans there and throws during parsing, preventing
/// the handshake from completing.
///
/// This transport rewrites those fields to `true` before handing the message to
/// `JsonRpcMessage.fromJson`, keeping behavior backward compatible.
final class CopilotCompatStdioServerTransport implements Transport {
  CopilotCompatStdioServerTransport({io.Stdin? stdin, io.IOSink? stdout})
    : _stdin = stdin ?? io.stdin,
      _stdout = stdout ?? io.stdout,
      _logger = logging.Logger('CopilotCompatStdioServerTransport');

  final io.Stdin _stdin;
  final io.IOSink _stdout;
  final logging.Logger _logger;

  bool _started = false;
  StreamSubscription<String>? _linesSubscription;

  @override
  void Function()? onclose;

  @override
  void Function(Error error)? onerror;

  @override
  void Function(JsonRpcMessage message)? onmessage;

  @override
  String? get sessionId => null;

  @override
  Future<void> start() async {
    if (_started) {
      throw StateError('CopilotCompatStdioServerTransport already started!');
    }
    _started = true;

    _linesSubscription = _stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: _onErrorCallback,
          onDone: _onStdinDone,
          cancelOnError: false,
        );
  }

  void _onLine(String line) {
    // Skip empty lines to be tolerant of clients that emit them.
    if (line.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('JSON-RPC message must be an object');
      }

      final messageMap = decoded.cast<String, dynamic>();
      _applyCopilotInitializeFixes(messageMap);

      final message = JsonRpcMessage.fromJson(messageMap);
      onmessage?.call(message);
    } catch (e, st) {
      final err = (e is Error)
          ? e
          : StateError('Message parsing error: $e\n$st');
      try {
        onerror?.call(err);
      } catch (handlerErr) {
        _logger.warning('Error within onerror handler: $handlerErr');
      }
      _logger.warning(
        'Failed to parse/process JSON-RPC line (continuing): $line',
        e,
        st,
      );
    }
  }

  void _applyCopilotInitializeFixes(Map<String, dynamic> json) {
    // Only touch initialize requests.
    if (json['method'] != Method.initialize) return;

    final params = json['params'];
    if (params is! Map) return;

    final capabilities = params['capabilities'];
    if (capabilities is! Map) return;

    final tasks = capabilities['tasks'];
    if (tasks is! Map) return;

    // Copilot sends these as objects `{}`; mcp_dart expects bool.
    for (final key in const ['list', 'cancel']) {
      final v = tasks[key];
      if (v is Map) {
        tasks[key] = true;
      }
    }
  }

  void _onErrorCallback(dynamic error, StackTrace stackTrace) {
    final Error dartError = (error is Error)
        ? error
        : StateError('Stdin error: $error\n$stackTrace');
    try {
      onerror?.call(dartError);
    } catch (e) {
      _logger.warning('Error within onerror handler: $e');
    }
  }

  void _onStdinDone() {
    _logger.fine('Stdin closed.');
    close();
  }

  @override
  Future<void> send(JsonRpcMessage message, {int? relatedRequestId}) {
    if (!_started) return Future.value();
    try {
      _stdout.write('${jsonEncode(message.toJson())}\n');
      return Future.value();
    } catch (e) {
      final Error dartError = e is Error
          ? e
          : StateError('Failed to send message: $e');
      try {
        onerror?.call(dartError);
      } catch (handlerErr) {
        _logger.warning(
          'Error within onerror handler during send: $handlerErr',
        );
      }
      return Future.error(dartError);
    }
  }

  @override
  Future<void> close() async {
    if (!_started) return;

    await _linesSubscription?.cancel();
    _linesSubscription = null;
    _started = false;

    try {
      onclose?.call();
    } catch (e) {
      _logger.warning('Error within onclose handler: $e');
    }
  }
}
