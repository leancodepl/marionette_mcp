import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';

/// Wraps a tool callback body in the standard error-handling boilerplate:
/// run the body, and on any throw log a warning and return a
/// [CallToolResult] with `isError: true` and the exception's message.
///
/// Used by tools that want the default failure semantics. Tools with
/// non-trivial mid-flow control (e.g. `connect` rolling back on a version
/// mismatch) should not use this helper.
Future<CallToolResult> runTool(
  logging.Logger logger,
  String operation,
  Future<CallToolResult> Function() body,
) async {
  try {
    return await body();
  } catch (err) {
    logger.warning('Failed to $operation', err);
    return CallToolResult(
      isError: true,
      content: [TextContent(text: err.toString())],
    );
  }
}
