import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'base_tool.dart';
import 'tool_results.dart';

/// Creates the system tools with their shared dependencies.
List<BaseTool> createSystemTools({
  required VmServiceConnector connector,
  required logging.Logger logger,
}) =>
    [HotReloadTool(connector, logger), HotRestartTool(connector, logger)];

/// MCP tool `hot_reload`.
class HotReloadTool extends BaseTool {
  HotReloadTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'hot_reload';

  @override
  String get description =>
      'Performs a hot reload of the Flutter app. This reloads the Dart code without restarting the app, preserving the current state. Useful after making code changes to see them reflected in the running app. Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations => const ToolAnnotations(title: 'Hot Reload');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    logger.info('Performing hot reload');

    try {
      final reloaded = await connector.hotReload();
      if (reloaded) {
        return messageResult('Hot reload completed successfully');
      }
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text: 'Hot reload failed. The app may need a full restart.',
          ),
        ],
      );
    } catch (err) {
      logger.warning('Failed to perform hot reload', err);
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Hot reload failed: $err')],
      );
    }
  }
}

/// MCP tool `hot_restart`.
class HotRestartTool extends BaseTool {
  HotRestartTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'hot_restart';

  @override
  String get description =>
      'Performs a hot restart of the Flutter app. This fully restarts the app from main() and resets all state. Use it instead of hot_reload after changes a reload cannot pick up (e.g. changes to main()/bootstrap, global singletons, or state shape). Requires the app to be running via `flutter run` and an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Hot Restart');

  @override
  ToolOutputSchema get outputSchema => messageOutputSchema;

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    logger.info('Performing hot restart');

    try {
      final restarted = await connector.hotRestart();
      if (restarted) {
        return messageResult('Hot restart completed successfully');
      }
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text: 'Hot restart failed or is unavailable. Make sure the '
                'app is running via `flutter run`.',
          ),
        ],
      );
    } catch (err) {
      logger.warning('Failed to perform hot restart', err);
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Hot restart failed: $err')],
      );
    }
  }
}
