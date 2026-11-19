import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/tools/notification_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import '../support/fake_native_connector.dart';

String _text(CallToolResult result) =>
    result.content.whereType<TextContent>().map((c) => c.text).join('\n');

void main() {
  late FakeNativeConnector connector;
  late FakeNativeDevice device;
  late NativeServiceContext context;

  setUp(() async {
    connector = FakeNativeConnector();
    device = connector.device;
    context = NativeServiceContext(
      connectorFactory: (platform, {serial, udid}) async => connector,
    );
    await context.connect(NativePlatform.android);
  });

  group('native_notifications', () {
    test('Android opens and closes the shade with commands', () async {
      await handleNativeNotifications(context, {'action': 'open'});
      await handleNativeNotifications(context, {'action': 'close'});
      expect(device.calls, ['openNotifications', 'closeNotifications']);
      expect(connector.swipes, isEmpty);
    });

    test('iOS delegates notification actions to its device', () async {
      await context.connect(NativePlatform.ios);

      await handleNativeNotifications(context, {'action': 'open'});
      await handleNativeNotifications(context, {'action': 'close'});

      expect(connector.swipes, isEmpty);
      expect(device.calls, ['openNotifications', 'closeNotifications']);
    });

    test('rejects an unknown action', () async {
      final result =
          await handleNativeNotifications(context, {'action': 'push'});
      expect(result.isError, isTrue);
      expect(_text(result), contains('"open" or "close"'));
    });
  });
}
