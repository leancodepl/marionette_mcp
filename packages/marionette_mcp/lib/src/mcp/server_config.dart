import 'package:args/args.dart';

/// Command-line configuration for the standalone Marionette MCP server.
class ServerConfig {
  const ServerConfig({this.logLevel = 'INFO', this.logFile, this.ssePort});

  /// Parses server options, rejecting an invalid SSE port instead of
  /// silently falling back to stdio.
  factory ServerConfig.fromResults(ArgResults results) {
    final rawPort = results.option('sse-port');
    final port = rawPort == null ? null : int.tryParse(rawPort);
    if (rawPort != null && (port == null || port < 0 || port > 65535)) {
      throw FormatException('SSE port must be an integer between 0 and 65535.');
    }
    return ServerConfig(
      logLevel: (results.option('log-level') ?? 'INFO').toUpperCase(),
      logFile: results.option('log-file'),
      ssePort: port,
    );
  }

  /// Logging verbosity, using the names from package:logging.
  final String logLevel;

  /// Optional log destination; otherwise records are written to stderr.
  final String? logFile;

  /// Legacy SSE listener port. Null selects the default stdio transport.
  final int? ssePort;

  /// Adds the common options to an executable or CLI subcommand parser.
  static void addOptions(ArgParser parser) {
    parser
      ..addOption('log-level',
          abbr: 'l',
          defaultsTo: 'INFO',
          help:
              'Log level (FINEST, FINER, FINE, CONFIG, INFO, WARNING, SEVERE).')
      ..addOption('log-file',
          help: 'Path to log file. If not set, logs to stderr.')
      ..addOption('sse-port',
          help: 'Port for SSE server. If not set, uses stdio transport.');
  }

  /// Builds the standalone executable parser.
  static ArgParser buildParser() {
    final parser = ArgParser()
      ..addFlag('help',
          abbr: 'h', negatable: false, help: 'Print this usage information.')
      ..addFlag('version', negatable: false, help: 'Print the tool version.');
    addOptions(parser);
    return parser;
  }
}
