import 'package:marionette_mcp/src/vm_service/tools/inspection_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('MCP result preserves the response as structured content', () {
    final response = <String, dynamic>{
      'schemaVersion': 1,
      'context': <String, Object?>{'route': '/checkout'},
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'Button', 'text': 'Continue'},
      ],
    };

    final result = buildInteractiveElementsToolResult(response);

    expect(result.structuredContent, same(response));
    expect(result.content.single, isA<TextContent>());
    expect(
      (result.content.single as TextContent).text,
      contains('Context: {"route":"/checkout"}'),
    );
  });
}
