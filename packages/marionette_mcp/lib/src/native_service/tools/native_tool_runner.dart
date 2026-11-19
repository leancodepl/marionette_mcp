import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// [runTool] for a native tool: a lost session or device-side server fails
/// with a hint to call `native_connect` again; other errors keep their own
/// message.
Future<CallToolResult> runNativeTool(
  logging.Logger logger,
  String operation,
  Future<CallToolResult> Function() body,
) =>
    runTool(logger, operation, () async {
      try {
        return await body();
      } on WebDriverException catch (exception, stackTrace) {
        if (!isLostSession(exception)) rethrow;
        logger.warning(
            'Native session lost during $operation', exception, stackTrace);
        throw NativeOperationFailedException(
          'The native session is gone (${exception.error}).',
          hint: 'Call native_connect again.',
        );
      }
    });
