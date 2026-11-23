import 'package:marionette_mcp/src/vm_service/vm_service_context.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'fake_vm_service.dart';

String _text(CallToolResult result) =>
    result.content.whereType<TextContent>().map((c) => c.text).join('\n');

void main() {
  late FakeVmService app;
  late VmServiceContext context;
  late McpClient client;

  setUp(() async {
    app = await FakeVmService.start();
    addTearDown(app.close);
    app.configuration = {
      'enableSessionReports': false,
      'uiLibraries': ['material_ui'],
    };
    context = VmServiceContext();
    client = await startTools(context);
  });

  Future<String> listElements() async => _text(
        await client.callTool(
          const CallToolRequest(name: 'get_interactive_elements'),
        ),
      );

  test('connect names a missing integration, and the listing until a restart',
      () async {
    final connected = await callConnect(
      client,
      app.uri,
      requiredUiLibraries: ['material_ui', 'cupertino_ui'],
    );

    expect(connected.isError, isFalse);
    expect(_text(connected), contains('flutter pub add marionette_cupertino'));
    expect(
      await listElements(),
      allOf(
        contains('Warning: UI integrations: missing cupertino_ui'),
        contains('Found 0 interactive element(s)'),
      ),
    );

    app.registerService('hotRestart', 's0.hotRestart');
    await client.callTool(const CallToolRequest(name: 'hot_restart'));

    expect(await listElements(), isNot(contains('Warning')));
  });

  test('connect rejects an unsupported required UI library', () async {
    await expectLater(
      callConnect(client, app.uri, requiredUiLibraries: ['swing_ui']),
      throwsA(
        isA<McpError>().having((e) => e.message, 'message', contains('one of')),
      ),
    );

    expect(context.connector.isConnected, isFalse);
  });
}
