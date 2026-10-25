import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/mcp.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Runs the Marionette MCP server with the given configuration.
///
/// Sets up logging, creates the MCP server with tools, and runs it on either
/// stdio or SSE transport depending on whether [ssePort] is provided.
Future<int> runMcpServer({
  required String logLevel,
  String? logFile,
  int? ssePort,
}) async {
  final logger = logging.Logger('main');
  StreamSubscription<logging.LogRecord>? logSubscription;
  VmServiceContext? context;
  McpServer? server;
  ExitSignal? exitSignal;
  _RunningTransport? transport;

  try {
    try {
      logSubscription = setupLogging(logLevel, logFile);
      context = VmServiceContext();
      server = createMcpServer(context: context);
      exitSignal = ExitSignal();
      transport = ssePort == null
          ? await _startStdioServer(server, logger)
          : await _startSseServer(server, ssePort, logger);

      final reason = await Future.any([
        exitSignal.wait.then((signal) => 'Received ${signal.name}'),
        transport.done.then(
            (_) => ssePort == null ? 'stdin closed' : 'HTTP listener closed'),
      ]);
      logger.info('$reason, stopping');
    } finally {
      exitSignal?.dispose();
      try {
        await transport?.close();
      } finally {
        // The app connection outlives individual tool calls. Its owner must
        // also cancel pending VM WebSocket upgrades during shutdown.
        try {
          await context?.dispose();
        } finally {
          await server?.close();
        }
      }
    }
    logger.info('Stopped');
    return 0;
  } catch (error, stackTrace) {
    if (logSubscription == null) {
      stderr.writeln('Error when starting MCP server: $error');
    } else {
      logger.severe('Error when running MCP server', error, stackTrace);
    }
    return 1;
  } finally {
    await logSubscription?.cancel();
  }
}

StreamSubscription<logging.LogRecord> setupLogging(
  String logLevelName,
  String? logFile,
) {
  final logLevel = logging.Level.LEVELS.firstWhere(
    (e) => e.name == logLevelName,
    orElse: () => logging.Level.INFO,
  );

  logging.Logger.root.level = logLevel;

  if (logFile != null) {
    final file = File(logFile)..createSync(recursive: true);
    return logging.Logger.root.onRecord.listen((record) {
      file.writeAsStringSync(
        '[${record.level.name}][${record.loggerName}][${_formatTime(record.time)}] ${record.message}\n',
        mode: FileMode.append,
      );
    });
  } else {
    return logging.Logger.root.onRecord.listen((record) {
      stderr.writeln(
        '[${record.level.name}][${record.loggerName}][${_formatTime(record.time)}] ${record.message}',
      );
    });
  }
}

String _formatTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

typedef _RunningTransport = ({
  Future<void> done,
  Future<void> Function() close,
});

Future<_RunningTransport> _startStdioServer(
  McpServer server,
  logging.Logger logger,
) async {
  final transport = StdioServerTransport();
  final stdinClosed = Completer<void>();
  final previousOnClose = server.server.onclose;

  // EOF may arrive during connect, so install the handler before starting.
  // Protocol.connect owns transport.onclose; use its public server callback.
  server.server.onclose = () {
    try {
      previousOnClose?.call();
    } finally {
      if (!stdinClosed.isCompleted) stdinClosed.complete();
    }
  };

  logger.fine('Running MCP server on stdio');
  await server.connect(transport);
  logger.info('Server started');
  return (done: stdinClosed.future, close: transport.close);
}

Future<_RunningTransport> _startSseServer(
  McpServer server,
  int port,
  logging.Logger logger,
) async {
  final manager = SseServerManager(server);
  final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  logger.fine('Running MCP server on SSE port $port');

  Future<void> serveRequests() async {
    await for (final request in listener) {
      unawaited(manager.handleRequest(request));
    }
  }

  Future<void> close() async {
    try {
      await listener.close(force: true);
    } finally {
      // Legacy SSE has no manager.stop API; close every active session.
      await Future.wait([
        for (final transport in manager.activeSseTransports.values.toList())
          transport.close(),
      ]);
    }
  }

  return (done: serveRequests(), close: close);
}

/// Waits for SIGINT or SIGTERM to signal graceful shutdown.
class ExitSignal {
  ExitSignal() {
    if (!Platform.isWindows) {
      _sigtermSubscription = ProcessSignal.sigterm.watch().listen(
            _handleSignal,
          );
    }
    _sigintSubscription = ProcessSignal.sigint.watch().listen(_handleSignal);
  }

  final _completer = Completer<ProcessSignal>();
  StreamSubscription<ProcessSignal>? _sigtermSubscription;
  late final StreamSubscription<ProcessSignal> _sigintSubscription;
  bool _disposed = false;

  Future<ProcessSignal> get wait => _completer.future;

  /// Cancels the signal subscriptions so they no longer keep the event loop
  /// alive. Safe to call multiple times — in normal operation it runs once
  /// from [_handleSignal] and again from the shutdown path.
  void dispose() => _cleanup();

  void _handleSignal(ProcessSignal signal) {
    if (!_completer.isCompleted) {
      _completer.complete(signal);
      _cleanup();
    }
  }

  void _cleanup() {
    if (_disposed) return;
    _disposed = true;
    _sigtermSubscription?.cancel();
    _sigintSubscription.cancel();
  }
}
