import 'dart:convert';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native UI hierarchy inspection tools.
void registerNativeInspectionTools(
  McpServer server,
  NativeServiceContext context,
  logging.Logger logger,
) {
  server.registerTool(
    'native_get_elements',
    description: 'Returns the native UI hierarchy as JSON: '
        '{ elements: [...], foregroundApp: string? }. '
        'Each element has type, optional text/id, bounds (physical px), '
        'and clickable. Use when the target is missing from '
        'get_interactive_elements or a system surface covers the app. '
        'foregroundApp (Android package / iOS bundle id) helps detect '
        'permission controllers and other system UIs on top of the Flutter '
        'app. Prefer Flutter get_interactive_elements first. '
        '$nativeRoutingPreferFlutter '
        'Requires native_connect.',
    annotations: const ToolAnnotations(
      title: 'Get Native Elements',
      readOnlyHint: true,
      idempotentHint: true,
    ),
    inputSchema: const ToolInputSchema(properties: {}),
    callback: (args, extra) async {
      logger.info('Getting native elements');
      return runTool(logger, 'get native elements', () async {
        final connector = context.requireConnector();
        final elements = await connector.getNativeElements();
        final foregroundApp = await connector.foregroundApp;
        final payload = <String, dynamic>{
          'elements': elements.map((e) => e.toJson()).toList(),
          'foregroundApp': foregroundApp,
        };
        return CallToolResult(
          content: [TextContent(text: jsonEncode(payload))],
        );
      });
    },
  );
}
