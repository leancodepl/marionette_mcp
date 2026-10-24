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
  final logSubscription = setupLogging(logLevel, logFile);

  final vmService = VmServiceContext();

  final server = createMcpServer(context: vmService);
  try {
    return ssePort == null
        ? await _runStdioServer(server)
        : await _runSseServer(server, ssePort);
  } finally {
    // The app connection outlives individual tool calls, so the server owns it.
    // Closing only the MCP transport leaves its VM-service socket alive.
    try {
      await vmService.dispose();
    } finally {
      try {
        await server.close();
      } finally {
        await logSubscription.cancel();
      }
    }
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

Future<int> _runStdioServer(McpServer server) async {
  final logger = logging.Logger('main');

  final transport = StdioServerTransport();
  final exitSignal = ExitSignal();
  final stdinClosed = Completer<void>();

  // Install the close handler before connecting. An immediate stdin EOF
  // (e.g. `</dev/null`) can close the transport during or right after
  // connect(); registering afterwards risks missing that close and hanging
  // until a signal. Fires when the transport closes — including stdin EOF,
  // i.e. the MCP host went away without sending a signal. Per the stdio
  // lifecycle the server should shut down then, not wait for SIGINT/SIGTERM.
  server.server.onclose = () {
    if (!stdinClosed.isCompleted) stdinClosed.complete();
  };

  try {
    logger.fine('Running MCP server on stdio');
    await server.connect(transport);
    logger.info('Server started');
  } catch (e, st) {
    logger.severe('Error when starting the Stdio transport', e, st);
    exitSignal.dispose();
    return 1;
  }

  // Stop on whichever happens first: an OS signal or the transport closing.
  // Only the first cause is logged — closing the server below re-triggers
  // `onclose`, which would otherwise log a misleading second reason.
  var stopping = false;
  void logStop(String reason) {
    if (stopping) return;
    stopping = true;
    logger.info('$reason, stopping');
  }

  await Future.any([
    exitSignal.wait.then((signal) => logStop('Received ${signal.name}')),
    stdinClosed.future.then((_) => logStop('stdin closed')),
  ]);

  // Release the signal subscriptions so the event loop can drain and the
  // process actually exits on the stdin-EOF path.
  exitSignal.dispose();
  await transport.close();
  logger.info('Stopped');
  return 0;
}

Future<int> _runSseServer(McpServer server, int ssePort) async {
  final logger = logging.Logger('main');
  final manager = SseServerManager(server);
  final exitSignal = ExitSignal();
  HttpServer? httpServer;
  try {
    final listener = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      ssePort,
    );
    httpServer = listener;
    logger.fine('Running MCP server on SSE port $ssePort');
    unawaited(exitSignal.wait.then((signal) async {
      logger.info('Received ${signal.name}, stopping');
      await listener.close(force: true);
    }));
    await for (final request in listener) {
      unawaited(manager.handleRequest(request));
    }
    logger.info('Stopped');
    return 0;
  } catch (e, st) {
    logger.severe('Error when waiting for MCP client connection', e, st);
    return 1;
  } finally {
    exitSignal.dispose();
    await httpServer?.close(force: true);
    await Future.wait([
      for (final transport in manager.activeSseTransports.values.toList())
        transport.close(),
    ]);
  }
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
