import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers text-input MCP tools: `enter_text`.
void registerTextTools(
  McpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server.registerTool(
    'enter_text',
    description:
        'Enters text into a text field in the Flutter app. You can target the field in three ways: 1. By key: provide the key parameter with the ValueKey<String> of the field. You can discover available keys by calling get_interactive_elements. 2. By Semantics identifier: provide the identifier parameter with the accessibility identifier of the field. Useful when the field has no ValueKey but does set a Semantics identifier. 3. By focused element: first tap a text field to give it focus, then call enter_text with focused_element set to true. Important: when targeting by focused element, a text field must be focused before calling this (for example by using the tap tool), otherwise it will fail with an error. Exactly one of key, identifier, or focused_element must be provided. Requires an active connection established via connect.',
    annotations: const ToolAnnotations(title: 'Enter Text'),
    inputSchema: ToolInputSchema(
      properties: {
        'input': JsonSchema.string(
          description: 'The text to enter into the text field.',
        ),
        'key': JsonSchema.string(
          description:
              'The key of the text field. You can get the key of an element by calling get_interactive_elements.',
        ),
        'identifier': JsonSchema.string(
          description:
              'The Semantics identifier of the text field. A stable, unique '
              'accessibility identifier set via Semantics(identifier: ...). '
              'You can discover identifiers by calling get_interactive_elements.',
        ),
        'focused_element': JsonSchema.boolean(
          description:
              'If true, enters text into the currently focused text field. '
              'A text field must be focused first (for example by using tap), otherwise this will fail.',
        ),
      },
      required: ['input'],
    ),
    callback: (args, extra) async {
      final input = args['input'] as String;
      final hasKey = args['key'] != null;
      final hasIdentifier = args['identifier'] != null;
      final hasFocusedElement = args['focused_element'] == true;

      final selectorCount =
          [hasKey, hasIdentifier, hasFocusedElement].where((e) => e).length;
      if (selectorCount != 1) {
        return CallToolResult(
          isError: true,
          content: [
            const TextContent(
              text:
                  'enter_text requires exactly one selector: provide key, identifier, or focused_element=true.',
            ),
          ],
        );
      }

      final matcher = buildMatcher(args);
      logger.info('Entering text into element with matcher: $matcher');
      return runTool(logger, 'enter text', () async {
        final response = await connector.enterText(matcher, input);
        final message = response['message'] as String?;
        return CallToolResult(
          content: [
            TextContent(text: message ?? 'Successfully entered text'),
          ],
        );
      });
    },
  );
}
