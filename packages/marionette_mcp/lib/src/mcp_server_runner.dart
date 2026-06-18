import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/compat/copilot_stdio_server_transport.dart';
import 'package:marionette_mcp/src/version.g.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_context.dart';
import 'package:mcp_dart/mcp_dart.dart';

const _instructions = '''
Marionette MCP enables AI agents to interact with Flutter apps running in debug mode. It provides tools to inspect UI elements, tap buttons, enter text, scroll, take screenshots, retrieve logs, and perform hot reloads and hot restarts.

Usage:
1. Start the Flutter app in debug mode and note the VM service URI (e.g., ws://127.0.0.1:8181/ws).
2. Use the "connect" tool with the VM service URI to establish a connection.
3. Use "get_interactive_elements" to discover available UI elements.
4. Interact with elements using "tap", "enter_text", or "scroll_to" tools.
5. Use "take_screenshots" to see the current app state and "get_logs" to debug issues.
6. Use "hot_reload" after making code changes to reload the app without losing state.
7. Use "hot_restart" to fully restart the app from main() and reset all state — needed for changes a hot reload cannot pick up (e.g. main()/bootstrap edits, global singletons, or state shape). Requires the app to be running via `flutter run`.

Important: Elements are matched by their key (ValueKey<String>) or text content. Keys are more reliable. If you cannot locate a widget, you may need to add a ValueKey to it in the Flutter source code. For example: `ElevatedButton(key: ValueKey('submit_button'), ...)`.
''';

/// Runs the Marionette MCP server with the given configuration.
///
/// Sets up logging, creates the MCP server with tools, and runs it on either
/// stdio or SSE transport depending on whether [ssePort] is provided.
Future<int> runMcpServer({
  required String logLevel,
  String? logFile,
  int? ssePort,
}) async {
  setupLogging(logLevel, logFile);

  final vmService = VmServiceContext();

  final server = McpServer(
    const Implementation(name: 'marionette-mcp', version: version),
    options: const McpServerOptions(
      // listChanged: true advertises that the tool set can change at
      // runtime — required for clients to refetch tools/list when an app
      // connects with custom extensions registered via
      // registerMarionetteExtension.
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
      ),
      instructions: _instructions,
    ),
  );

  vmService.registerTools(server);

  if (ssePort != null) {
    return _runSseServer(server, ssePort);
  } else {
    return _runStdioServer(server);
  }
}

void setupLogging(String logLevelName, String? logFile) {
  final logLevel = logging.Level.LEVELS.firstWhere(
    (e) => e.name == logLevelName,
    orElse: () => logging.Level.INFO,
  );

  logging.Logger.root.level = logLevel;

  if (logFile != null) {
    final file = File(logFile)..createSync(recursive: true);
    logging.Logger.root.onRecord.listen((record) {
      file.writeAsStringSync(
        '[${record.level.name}][${record.loggerName}][${_formatTime(record.time)}] ${record.message}\n',
        mode: FileMode.append,
      );
    });
  } else {
    logging.Logger.root.onRecord.listen((record) {
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

  final transport = CopilotCompatStdioServerTransport();

  try {
    logger.fine('Running MCP server on stdio');
    await server.connect(transport);
    logger.info('Server started');
  } catch (e, st) {
    logger.severe('Error when starting the Stdio transport', e, st);
    return 1;
  }

  // Stop on either an OS signal (SIGINT/SIGTERM) or the client closing the
  // connection (stdin EOF). MCP hosts shut a stdio server down by closing its
  // stdin; honoring that is required so the process exits when the host goes
  // away without sending a signal (e.g. the host is killed and this process is
  // reparented to init), instead of lingering idle forever.
  // See https://github.com/leancodepl/marionette_mcp/issues/84.
  final exitSignal = ExitSignal();
  final reason = await Future.any([
    exitSignal.wait.then((signal) => 'Received ${signal.name}'),
    transport.done.then((_) => 'stdin closed'),
  ]);
  exitSignal.dispose();
  logger.info('$reason, stopping');

  await server.close();
  await transport.close();
  logger.info('Stopped');
  return 0;
}

Future<int> _runSseServer(McpServer server, int ssePort) async {
  final logger = logging.Logger('main');
  final sseServerManager = SseServerManager(server);
  try {
    final httpServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      ssePort,
    );
    logger.fine('Running MCP server on SSE port $ssePort');
    unawaited(
      ExitSignal().wait.then((signal) {
        logger.info('Received ${signal.name}, stopping');
        unawaited(httpServer.close());
      }),
    );

    await for (final request in httpServer) {
      unawaited(sseServerManager.handleRequest(request));
    }

    logger.info('Stopping');
    await server.close();
  } catch (e, st) {
    logger.severe('Error when waiting for MCP client connection', e, st);
    return 1;
  }

  logger.info('Stopped');
  return 0;
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

  Future<ProcessSignal> get wait => _completer.future;

  /// Cancels the signal subscriptions. Must be called when shutting down for a
  /// reason other than a caught signal (e.g. stdin EOF); otherwise the watch
  /// subscriptions keep the Dart event loop alive and the process never exits.
  void dispose() => _cleanup();

  void _handleSignal(ProcessSignal signal) {
    if (!_completer.isCompleted) {
      _completer.complete(signal);
      _cleanup();
    }
  }

  void _cleanup() {
    _sigtermSubscription?.cancel();
    _sigintSubscription.cancel();
  }
}
