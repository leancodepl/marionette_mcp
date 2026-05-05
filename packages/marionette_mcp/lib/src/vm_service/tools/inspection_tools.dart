import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers read-only MCP tools that inspect the running app:
/// `get_interactive_elements`, `get_logs`, `take_screenshots`.
void registerInspectionTools(
  McpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server
    ..registerTool(
      'get_interactive_elements',
      description:
          'Returns a list of all interactive elements currently visible in the Flutter app UI tree. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Get Interactive Elements',
        readOnlyHint: true,
        idempotentHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Getting interactive elements');
        return runTool(logger, 'get interactive elements', () async {
          final response = await connector.getInteractiveElements();
          final elements = response['elements'] as List<dynamic>;

          final buffer = StringBuffer()
            ..writeln('Found ${elements.length} interactive element(s):\n');

          for (final element in elements) {
            buffer.writeln(formatElement(element as Map<String, dynamic>));
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
          );
        });
      },
    )
    ..registerTool(
      'get_logs',
      description:
          'Retrieves all application logs collected from the Flutter app since app start or since the last hot reload. This includes debug messages, errors, and other log output from the running app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Get Application Logs',
        readOnlyHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Getting application logs');

        try {
          final response = await connector.getLogs();
          final logs = response['logs'] as List;
          final count = response['count'] as int;

          if (count == 0) {
            return CallToolResult(
              content: [const TextContent(text: 'No logs collected')],
            );
          }

          final buffer = StringBuffer()
            ..writeln(
              'Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n',
            );

          for (final log in logs) {
            buffer.writeln(log);
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
          );
        } on VmServiceExtensionException catch (err) {
          // Surface the VM service's own error message verbatim — it carries
          // setup instructions for enabling log collection.
          logger.warning('Failed to get logs', err);
          return CallToolResult(
            isError: true,
            content: [TextContent(text: err.error ?? err.message)],
          );
        } catch (err) {
          logger.warning('Failed to get logs', err);
          return CallToolResult(
            isError: true,
            content: [TextContent(text: err.toString())],
          );
        }
      },
    )
    ..registerTool(
      'take_screenshots',
      description:
          'Takes screenshots of all views in the Flutter app. Returns base64-encoded PNG images that can be decoded and saved. This captures the current visual state of the app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Take Screenshots',
        readOnlyHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Taking screenshots');
        return runTool(logger, 'take screenshots', () async {
          final response = await connector.takeScreenshots();
          final screenshots =
              (response['screenshots'] as List<dynamic>).cast<String>();

          if (screenshots.isEmpty) {
            return CallToolResult(
              content: [const TextContent(text: 'No screenshots captured')],
            );
          }
          return CallToolResult(
            content: screenshots
                .map(
                  (screenshot) =>
                      ImageContent(data: screenshot, mimeType: 'image/png'),
                )
                .toList(),
          );
        });
      },
    );
}
