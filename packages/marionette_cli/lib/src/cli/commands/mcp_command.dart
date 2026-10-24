import 'package:args/command_runner.dart';
import 'package:marionette_mcp/marionette_mcp.dart';

class McpCommand extends Command<int> {
  McpCommand() {
    ServerConfig.addOptions(argParser);
  }

  @override
  String get name => 'mcp';

  @override
  String get description =>
      'Run the Marionette MCP server (stdio or SSE transport).';

  @override
  Future<int> run() async {
    final config = ServerConfig.fromResults(argResults!);
    return runMcpServer(
      logLevel: config.logLevel,
      logFile: config.logFile,
      ssePort: config.ssePort,
    );
  }
}
