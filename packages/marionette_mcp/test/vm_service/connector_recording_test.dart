import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

/// A mock connector that records startScreencast/stopScreencast calls.
class RecordingConnector implements VmServiceConnector {
  final startScreencastCalls =
      <({int? maxWidth, int? maxHeight, int? wsPort})>[];
  int stopScreencastCallCount = 0;
  Map<String, dynamic> nextResponse = {};

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    startScreencastCalls.add((
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      wsPort: wsPort,
    ));
    return nextResponse;
  }

  @override
  Future<Map<String, dynamic>> stopScreencast() async {
    stopScreencastCallCount++;
    return nextResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('VmServiceConnector', () {
    group('Given a connected connector', () {
      late RecordingConnector connector;

      setUp(() {
        connector = RecordingConnector();
      });

      test('When startScreencast is called, '
          'Then the call is recorded', () async {
        await connector.startScreencast();

        expect(connector.startScreencastCalls, hasLength(1));
      });

      test('When startScreencast is called with maxWidth and maxHeight, '
          'Then they are passed through', () async {
        await connector.startScreencast(maxWidth: 400, maxHeight: 300);

        final call = connector.startScreencastCalls.first;
        expect(call.maxWidth, 400);
        expect(call.maxHeight, 300);
      });

      test('When startScreencast is called with wsPort, '
          'Then wsPort is passed through', () async {
        await connector.startScreencast(wsPort: 9876);

        final call = connector.startScreencastCalls.first;
        expect(call.wsPort, 9876);
      });

      test('When startScreencast is called without wsPort, '
          'Then wsPort is null', () async {
        await connector.startScreencast();

        final call = connector.startScreencastCalls.first;
        expect(call.wsPort, isNull);
      });

      test('When stopScreencast is called, '
          'Then the call is recorded', () async {
        await connector.stopScreencast();

        expect(connector.stopScreencastCallCount, equals(1));
      });
    });

    group('Given a disconnected connector', () {
      late VmServiceConnector connector;

      setUp(() {
        connector = VmServiceConnector();
      });

      test('When startScreencast is called, '
          'Then it throws NotConnectedException', () async {
        await expectLater(
          connector.startScreencast(),
          throwsA(isA<NotConnectedException>()),
        );
      });

      test('When stopScreencast is called, '
          'Then it throws NotConnectedException', () async {
        await expectLater(
          connector.stopScreencast(),
          throwsA(isA<NotConnectedException>()),
        );
      });
    });
  });
}
