import 'dart:convert';

import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native UI hierarchy inspection tools.
void registerNativeInspectionTools(
  McpServer server,
  NativeServiceContext context,
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
    callback: (args, extra) => handleNativeGetElements(context),
  );
}

/// Handles `native_get_elements`.
Future<CallToolResult> handleNativeGetElements(
  NativeServiceContext context,
) {
  final logger = context.logger;
  logger.info('Getting native elements');
  return runTool(logger, 'get native elements', () async {
    final connector = context.requireConnector();
    // foregroundApp is a diagnostic hint: fetch it alongside the tree and
    // report null rather than failing the whole call when it is unavailable.
    final foregroundApp = connector.foregroundApp
        .then<String?>((value) => value, onError: (Object _) => null);
    final elements = await connector.getNativeElements();
    final payload = <String, dynamic>{
      'elements': elements.map((e) => e.toJson()).toList(),
      'foregroundApp': await foregroundApp,
    };
    return CallToolResult(
      content: [TextContent(text: jsonEncode(payload))],
    );
  });
}
