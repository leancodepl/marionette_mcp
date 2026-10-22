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

    test('iOS swipes the Notification Center', () async {
      await context.connect(NativePlatform.ios);

      await handleNativeNotifications(context, {'action': 'open'});
      await handleNativeNotifications(context, {'action': 'close'});

      expect(connector.swipes, [
        (startX: 333, startY: 1, endX: 333, endY: 1200),
        // Up from the bottom edge: a swipe in the middle only scrolls the
        // notification list.
        (startX: 500, startY: 1999, endX: 500, endY: 1000),
      ]);
      expect(device.calls, isEmpty);
    });

    test('iOS retries a swipe that did not open it from the home screen',
        () async {
      // Seen on iOS 26.4: with a banner on screen, the first swipe missed.
      connector
        ..foregroundAppValue = 'com.apple.springboard'
        ..onGetElements = (_) => [
              if (connector.swipes.length > 1)
                nativeElement(
                  type: 'XCUIElementTypeWindow',
                  id: 'SBCoverSheetWindow',
                ),
            ];
      await context.connect(NativePlatform.ios);

      final result = await handleNativeNotifications(context, {
        'action': 'open',
      });

      expect(result.isError, isNot(true));
      expect(connector.swipes, hasLength(2));
    });

    test('iOS reports a Notification Center that did not open', () async {
      connector.foregroundAppValue = 'com.apple.springboard';
      await context.connect(NativePlatform.ios);

      final result = await handleNativeNotifications(context, {
        'action': 'open',
      });

      expect(result.isError, isTrue);
      expect(_text(result), contains('did not open'));
    });

    test('iOS explains notification groups, Android does not', () async {
      final android =
          _text(await handleNativeNotifications(context, {'action': 'open'}));
      await context.connect(NativePlatform.ios);
      final ios =
          _text(await handleNativeNotifications(context, {'action': 'open'}));

      expect(android, isNot(contains('group')));
      expect(ios, contains('the first tap on a group expands it'));
      expect(ios, contains('swiping it right'));
    });

    test('rejects an unknown action', () async {
      final result =
          await handleNativeNotifications(context, {'action': 'push'});
      expect(result.isError, isTrue);
      expect(_text(result), contains('"open" or "close"'));
    });
  });
}
