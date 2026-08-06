import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:test/test.dart';

class _FakeNativeConnector implements NativeConnector {
  var disposed = false;

  @override
  Future<List<NativeElement>> getNativeElements() async => const [];

  @override
  Future<String?> get foregroundApp async => 'com.example.app';

  @override
  Future<void> tapElement(NativeElement element) async {}

  @override
  Future<void> tapAt(int x, int y) async {}

  @override
  Future<void> enterText(NativeElement element, String text) async {}

  @override
  Future<void> swipe({
    required int startX,
    required int startY,
    required int endX,
    required int endY,
    int durationMs = 300,
  }) async {}

  @override
  Future<String> takeScreenshot() async => 'fake-png-base64';

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  group('NativeServiceContext', () {
    test('requireConnector throws when disconnected', () {
      final context = NativeServiceContext();
      expect(
        context.requireConnector,
        throwsA(isA<NativeNotConnectedException>()),
      );
    });

    test('dispose tears down the active connector', () async {
      final context = NativeServiceContext();
      final connector = _FakeNativeConnector();
      context.connector = connector;

      expect(context.requireConnector(), same(connector));

      await context.dispose();
      expect(context.connector, isNull);
      expect(connector.disposed, isTrue);
      expect(
        context.requireConnector,
        throwsA(isA<NativeNotConnectedException>()),
      );
    });
  });
}
