import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers MCP tools that control the Flutter app's dev workflow rather
/// than its UI: `hot_reload` and `hot_restart`.
void registerSystemTools(
  McpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server
    ..registerTool(
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
    )
    ..registerTool(
      'hot_restart',
      description:
          'Performs a hot restart of the Flutter app. This fully restarts the app from main() and resets all state. Use it instead of hot_reload after changes a reload cannot pick up (e.g. changes to main()/bootstrap, global singletons, or state shape). Requires the app to be running via `flutter run` and an active connection established via connect.',
      annotations: const ToolAnnotations(title: 'Hot Restart'),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Performing hot restart');

        try {
          final restarted = await connector.hotRestart();
          if (restarted) {
            return CallToolResult(
              content: [
                const TextContent(text: 'Hot restart completed successfully'),
              ],
            );
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
      },
    );
}
