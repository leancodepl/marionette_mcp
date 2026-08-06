import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/tools/native_tool_routing.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers native text-entry tools.
void registerNativeTextTools(
  McpServer server,
  NativeServiceContext context,
  logging.Logger logger,
) {
  server.registerTool(
    'native_enter_text',
    description: 'Types into a native / system text field. Provide text (the string '
        'to type) plus exactly one target: id (Android resource-id / iOS '
        'accessibility id) OR label (exact field label text from '
        'native_get_elements). Targets only native and system text fields '
        '— not Flutter TextFields. '
        '$nativeRoutingPreferFlutter '
        'Requires native_connect.',
    annotations: const ToolAnnotations(title: 'Native Enter Text'),
    inputSchema: ToolInputSchema(
      properties: {
        'text': JsonSchema.string(
          description: 'The text to type into the native field.',
        ),
        'id': JsonSchema.string(
          description: 'Exact Android resource-id or iOS accessibility id of the '
              'field, as returned in the "id" field of native_get_elements.',
        ),
        'label': JsonSchema.string(
          description: 'Exact visible label / text of the field to type into, as '
              'returned by native_get_elements. Use when the field has no '
              'stable id.',
        ),
      },
      required: ['text'],
    ),
    callback: (args, extra) async {
      final input = args['text'] as String?;
      final id = args['id'] as String?;
      final label = args['label'] as String?;

      if (input == null) {
        return CallToolResult(
          isError: true,
          content: [
            const TextContent(
              text: 'native_enter_text requires "text" (the string to type).',
            ),
          ],
        );
      }

      final hasId = id != null;
      final hasLabel = label != null;
      if (hasId == hasLabel) {
        return CallToolResult(
          isError: true,
          content: [
            const TextContent(
              text: 'native_enter_text requires exactly one target: '
                  'id or label (field label text).',
            ),
          ],
        );
      }

      logger.info('Native enter text target id=$id label=$label');
      return runTool(logger, 'native enter text', () async {
        final connector = context.requireConnector();
        final elements = await connector.getNativeElements();
        final NativeElement match;
        if (hasId) {
          match = elements.firstWhere(
            (e) => e.resourceId == id,
            orElse: () => throw StateError(
              'No native element with id="$id". '
              'Call native_get_elements and retry.',
            ),
          );
        } else {
          match = elements.firstWhere(
            (e) => e.text == label,
            orElse: () => throw StateError(
              'No native element with text="$label". '
              'Call native_get_elements and retry.',
            ),
          );
        }

        await connector.enterText(match, input);
        return CallToolResult(
          content: [
            TextContent(
              text: hasId
                  ? 'Successfully entered text into native field id="$id"'
                  : 'Successfully entered text into native field '
                      'label="$label"',
            ),
          ],
        );
      });
    },
  );
}
