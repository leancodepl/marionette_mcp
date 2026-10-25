/// Marionette MCP server composition and startup.
library;

export 'src/mcp/mcp.dart' show createMcpServer, registerMcpTools;
export 'src/mcp/server_config.dart' show ServerConfig;
export 'src/mcp/server_context.dart' show VmServiceContext;
export 'src/mcp/server_runner.dart' show runMcpServer;
export 'src/version.g.dart' show version;
