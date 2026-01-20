import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/compat/copilot_stdio_server_transport.dart';
import 'package:marionette_mcp/src/version.g.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_context.dart';
import 'package:mcp_dart/mcp_dart.dart';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag('version', negatable: false, help: 'Print the tool version.')
    ..addOption(
      'log-level',
      abbr: 'l',
      defaultsTo: 'INFO',
      help: 'Log level (FINEST, FINER, FINE, CONFIG, INFO, WARNING, SEVERE).',
    )
    ..addOption(
      'log-file',
      help: 'Path to log file. If not set, logs to stderr.',
    )
    ..addOption(
      'sse-port',
      help: 'Port for SSE server. If not set, uses stdio transport.',
    );
}

void printUsage(ArgParser argParser) {
  stderr
    ..writeln('Marionette MCP Server - Flutter app interaction for AI agents')
    ..writeln()
    ..writeln('Usage: marionette_mcp [options]')
    ..writeln()
    ..writeln('Options:')
    ..writeln(argParser.usage);
}

Future<int> main(List<String> arguments) async {
  final argParser = buildParser();
  try {
    final results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return 0;
    }
    if (results.flag('version')) {
      stderr.writeln('marionette_mcp version: $version');
      return 0;
    }

    final logLevelName = (results.option('log-level') ?? 'INFO').toUpperCase();
    final logFile = results.option('log-file');
    final ssePortStr = results.option('sse-port');
    final ssePort = ssePortStr != null ? int.tryParse(ssePortStr) : null;

    setupLogging(logLevelName, logFile);

    final vmService = VmServiceContext();

    final server = McpServer(
      const Implementation(name: 'marionette-mcp', version: version),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        instructions: '''
Marionette MCP enables AI agents to interact with Flutter apps running in debug mode. It provides tools to inspect UI elements, tap buttons, enter text, scroll, take screenshots, retrieve logs, and perform hot reloads.

Usage:
1. Start the Flutter app in debug mode and note the VM service URI (e.g., ws://127.0.0.1:8181/ws).
2. Use the "connect" tool with the VM service URI to establish a connection.
3. Use "get_interactive_elements" to discover available UI elements.
4. Interact with elements using "tap", "enter_text", or "scroll_to" tools.
5. Use "take_screenshots" to see the current app state and "get_logs" to debug issues.
6. Use "hot_reload" after making code changes to reload the app without losing state.

Important: Elements are matched by their key (ValueKey<String>) or text content. Keys are more reliable. If you cannot locate a widget, you may need to add a ValueKey to it in the Flutter source code. For example: `ElevatedButton(key: ValueKey('submit_button'), ...)`.
''',
      ),
    );

    vmService.registerTools(server);

    if (ssePort != null) {
      return await runSseServer(server, ssePort);
    } else {
      return await runStdioServer(server);
    }
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln();
    printUsage(argParser);
    return 1;
  } on Exception catch (e) {
    stderr.writeln(e.toString());
    return 1;
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

Future<int> runStdioServer(McpServer server) async {
  final logger = logging.Logger('main');

  // Use a stdio transport with small compatibility fixes for clients like Copilot.
  final transport = CopilotCompatStdioServerTransport();

  try {
    logger.fine('Running MCP server on stdio');
    await server.connect(transport);
    logger.info('Server started');
  } catch (e, st) {
    logger.severe('Error when starting the Stdio transport', e, st);
    return 1;
  }

  final signal = await _ExitSignal().wait;
  logger.info('Received ${signal.name}, stopping');

  await server.close();
  await transport.close();
  logger.info('Stopped');
  return 0;
}

Future<int> runSseServer(McpServer server, int ssePort) async {
  final logger = logging.Logger('main');
  final sseServerManager = SseServerManager(server);
  try {
    final httpServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      ssePort,
    );
    logger.fine('Running MCP server on SSE port $ssePort');
    unawaited(
      _ExitSignal().wait.then((signal) {
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

class _ExitSignal {
  _ExitSignal() {
    // SIGTERM is not supported on Windows, only listen on non-Windows platforms
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
