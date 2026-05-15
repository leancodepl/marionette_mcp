import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/version.g.dart' as v;
import 'package:marionette_mcp/src/vm_service/tools/extension_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/gesture_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/permission_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/system_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/text_tools.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Context for managing VM service connection and registering MCP tools.
final class VmServiceContext {
  VmServiceContext()
      : connector = VmServiceConnector(),
        _logger = logging.Logger('VmServiceContext');

  final VmServiceConnector connector;
  final logging.Logger _logger;

  /// Registers all VM service related tools with the MCP server.
  ///
  /// Connection lifecycle tools (`connect`, `disconnect`) are registered here
  /// because they own the version-compatibility handshake with the binding
  /// and don't fit the standard tool error-handling shape. Everything else
  /// is delegated to themed registration functions.
  void registerTools(McpServer server) {
    _registerConnectionTools(server);
    registerInspectionTools(server, connector, _logger);
    registerGestureTools(server, connector, _logger);
    registerTextTools(server, connector, _logger);
    registerExtensionTools(server, connector, _logger);
    registerSystemTools(server, connector, _logger);
    registerPermissionTools(server, _logger);
  }

  void _registerConnectionTools(McpServer server) {
    server
      ..registerTool(
        'connect',
        description:
            'Connects to a Flutter app via its VM service URI. This must be called before using any other tools. The VM service URI is typically in the format ws://127.0.0.1:PORT/ws and can be found in the Flutter app output when running in debug mode.',
        annotations: const ToolAnnotations(title: 'Connect to App'),
        inputSchema: ToolInputSchema(
          properties: {
            'uri': JsonSchema.string(
              description:
                  'VM service URI (e.g., ws://127.0.0.1:8181/ws). This is printed in the Flutter app console when running in debug mode.',
            ),
          },
          required: ['uri'],
        ),
        callback: (args, extra) async {
          final uri = args['uri'] as String;
          _logger.info('Connecting to app at $uri');

          try {
            await connector.connect(uri);

            // Version compatibility check — unwind the connection on mismatch
            // so the next call to connect can start fresh.
            try {
              final bindingVersion = await connector.getVersion();
              if (bindingVersion != v.version) {
                await connector.disconnect();
                return CallToolResult(
                  isError: true,
                  content: [
                    TextContent(
                      text: 'Version mismatch: marionette_mcp is ${v.version}, '
                          'but marionette_flutter binding is $bindingVersion. '
                          'Please ensure both packages are the same version.',
                    ),
                  ],
                );
              }
            } catch (err) {
              _logger.warning('Failed to check binding version', err);
              await connector.disconnect();
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'Failed to verify marionette_flutter binding version. '
                        'Please ensure marionette_flutter is up to date. '
                        'Error: $err',
                  ),
                ],
              );
            }

            return CallToolResult(
              content: [
                TextContent(text: 'Successfully connected to app at $uri'),
              ],
            );
          } catch (err) {
            _logger.severe('Failed to connect to app', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to connect to app: $err')],
            );
          }
        },
      )
      ..registerTool(
        'disconnect',
        description:
            'Disconnects from the currently connected Flutter app. After disconnecting, you must call connect again to use any other tools.',
        annotations: const ToolAnnotations(title: 'Disconnect from App'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Disconnecting from app');

          try {
            await connector.disconnect();
            return CallToolResult(
              content: [
                const TextContent(text: 'Successfully disconnected from app'),
              ],
            );
          } catch (err) {
            _logger.severe('Error during disconnect', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Error during disconnect: $err')],
            );
          }
        },
      );
  }
}
