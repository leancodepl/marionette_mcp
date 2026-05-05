import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers MCP tools that control the Flutter app's dev workflow rather
/// than its UI: `hot_reload`.
void registerSystemTools(
  McpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server.registerTool(
    'hot_reload',
    description:
        'Performs a hot reload of the Flutter app. This reloads the Dart code without restarting the app, preserving the current state. Useful after making code changes to see them reflected in the running app. Requires an active connection established via connect.',
    annotations: const ToolAnnotations(title: 'Hot Reload'),
    inputSchema: const ToolInputSchema(properties: {}),
    callback: (args, extra) async {
      logger.info('Performing hot reload');

      try {
        final reloaded = await connector.hotReload();
        if (reloaded) {
          return CallToolResult(
            content: [
              const TextContent(text: 'Hot reload completed successfully'),
            ],
          );
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
    },
  );
}
