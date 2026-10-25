/// Typed MCP tool contracts and registration.
library;

import 'package:mcp_dart/mcp_dart.dart';

/// Defines a tool's metadata, schemas, and execution.
abstract class BaseTool {
  /// Unique name for this tool.
  String get name;

  /// Human-readable description of what this tool does.
  String? get description;

  /// Object schema for tool arguments.
  ToolInputSchema get inputSchema;

  /// Optional JSON schema defining the output format.
  ToolOutputSchema? get outputSchema => null;

  /// Optional hints about tool behavior.
  ToolAnnotations? get annotations => null;

  /// Optional metadata for the tool.
  Map<String, dynamic>? get meta => null;

  /// Executes validated arguments and returns MCP content or a tool error.
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  );
}

/// Registers typed tools with an MCP server.
extension ToolRegistration on McpServer {
  /// Registers [tool], optionally wrapping execution with [callback].
  RegisteredTool registerBaseTool(BaseTool tool, {ToolFunction? callback}) {
    return registerTool(
      tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema,
      outputSchema: tool.outputSchema,
      annotations: tool.annotations,
      meta: tool.meta,
      callback: callback ?? tool.execute,
    );
  }
}
