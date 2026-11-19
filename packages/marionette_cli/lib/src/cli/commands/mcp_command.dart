import 'package:args/command_runner.dart';
import 'package:marionette_mcp/src/mcp_server_runner.dart';

/// Starts the MCP server; [runMcpServer] outside tests.
typedef McpServerRunner = Future<int> Function({
  required String logLevel,
  required bool enableNativeLane,
  String? logFile,
  int? ssePort,
});

class McpCommand extends Command<int> {
  McpCommand({McpServerRunner runServer = runMcpServer})
      : _runServer = runServer {
    argParser
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
      )
      ..addFlag(
        'native',
        defaultsTo: true,
        help: 'Register the native lane tools (native_*). '
            '--no-native leaves them and their instructions out.',
      );
  }

  final McpServerRunner _runServer;

  @override
  String get name => 'mcp';

  @override
  String get description =>
      'Run the Marionette MCP server (stdio or SSE transport).';

  @override
  Future<int> run() async {
    final logLevel = (argResults!.option('log-level') ?? 'INFO').toUpperCase();
    final logFile = argResults!.option('log-file');
    final ssePortStr = argResults!.option('sse-port');
    final ssePort = ssePortStr != null ? int.tryParse(ssePortStr) : null;
    final enableNativeLane = argResults!.flag('native');

    return _runServer(
      logLevel: logLevel,
      enableNativeLane: enableNativeLane,
      logFile: logFile,
      ssePort: ssePort,
    );
  }
}
