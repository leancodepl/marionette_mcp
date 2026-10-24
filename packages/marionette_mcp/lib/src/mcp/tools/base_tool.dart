/// Base class for MCP tools with dependency injection.
///
/// Each tool implementation should extend this class and provide:
/// - [name]: Unique tool identifier
/// - [description]: Human-readable description of what the tool does
/// - [inputSchema]: JSON schema for tool arguments
/// - [outputSchema]: Optional JSON schema for tool output
/// - [annotations]: Optional tool behavior hints (readOnly, destructive, etc.)
/// - [meta]: Optional metadata for the tool
/// - [execute]: Implementation of the tool logic
library;

import 'package:mcp_dart/mcp_dart.dart';

/// Base class for all MCP tools.
abstract class BaseTool {
  /// Unique name for this tool.
  String get name;

  /// Human-readable description of what this tool does.
  String? get description;

  /// JSON schema defining the input arguments.
  /// Use [JsonSchema.object()] to create an object schema.
  ToolInputSchema get inputSchema;

  /// Optional JSON schema defining the output format.
  ToolOutputSchema? get outputSchema => null;

  /// Optional tool annotations with hints about tool behavior.
  /// Includes readOnlyHint, destructiveHint, idempotentHint, etc.
  ToolAnnotations? get annotations => null;

  /// Optional metadata for the tool.
  Map<String, dynamic>? get meta => null;

  /// Execute the tool with the given arguments.
  ///
  /// Returns a [CallToolResult] with either success content or an error.
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  );
}

/// Extension to register tools with an MCP server.
extension ToolRegistration on McpServer {
  /// Register a [BaseTool] with this server.
  ///
  /// Use [callback] to wrap execution with shared concerns such as logging.
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
