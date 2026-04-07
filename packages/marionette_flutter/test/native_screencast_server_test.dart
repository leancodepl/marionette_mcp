import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/native_screencast_server.dart';

import 'screencast_test_helpers.dart';

/// Creates a [NativeScreencastServer] with a fake service and viewport provider.
NativeScreencastServer createNativeServer({
  FakeScreencastService? service,
  Size viewportSize = const Size(800, 600),
  void Function(Size? maxSize)? onFactoryCall,
}) {
  return NativeScreencastServer(
    screencastServiceFactory: ({Size? maxSize}) {
      onFactoryCall?.call(maxSize);
      return service ?? FakeScreencastService();
    },
    viewportSizeProvider: () => viewportSize,
  );
}

// ---------------------------------------------------------------------------
// Tests
//
// Use test() not testWidgets() — real I/O is incompatible with FakeAsync.
// ---------------------------------------------------------------------------

void main() {
  group('NativeScreencastServer', () {
    group('Given startScreencast() without wsPort', () {
      test('When called, Then delegates to TCP path and returns port',
          () async {
        final server = createNativeServer();

        final result = await server.startScreencast();

        expect(result['transport'], equals('tcp'));
        expect(result['port'], isA<int>());
        expect((result['port'] as int), greaterThan(0));
        expect(result['viewportWidth'], equals(800));
        expect(result['viewportHeight'], equals(600));

        await server.stopScreencast();
      });
    });

    group('Given startScreencast(wsPort: X) with wsPort', () {
      test('When called, Then delegates to WS path and returns transport ws',
          () async {
        final wsServer = await FakeWsServer.bind();
        final server = createNativeServer();

        try {
          final result = await server.startScreencast(wsPort: wsServer.port);

          expect(result['transport'], equals('ws'));
          expect(result['viewportWidth'], equals(800));
          expect(result['viewportHeight'], equals(600));
        } finally {
          await server.stopScreencast();
          await wsServer.close();
        }
      });
    });

    group('Given delegate switching', () {
      test(
          'When TCP start → stop → WS start, Then second call uses WS delegate',
          () async {
        final wsServer = await FakeWsServer.bind();
        final server = createNativeServer();

        try {
          // First call: TCP (no wsPort).
          final tcpResult = await server.startScreencast();
          expect(tcpResult['transport'], equals('tcp'));
          expect(server.isActive, isTrue);

          await server.stopScreencast();
          expect(server.isActive, isFalse);

          // Second call: WS (with wsPort).
          final wsResult = await server.startScreencast(wsPort: wsServer.port);
          expect(wsResult['transport'], equals('ws'));
          expect(server.isActive, isTrue);
        } finally {
          await server.stopScreencast();
          await wsServer.close();
        }
      });
    });

    group('Given delegate startScreencast fails', () {
      test(
          'When WS connection is refused, Then server recovers and can be restarted',
          () async {
        final server = createNativeServer();

        // Use an unused port so the WS connection is refused.
        await expectLater(
          () => server
              .startScreencast(wsPort: 1)
              .timeout(const Duration(seconds: 6)),
          throwsA(isA<Exception>()),
        );

        // Delegate should have been cleaned up — server should not be stuck
        // in "already active" state.
        expect(server.isActive, isFalse);

        // Should be able to start fresh with TCP.
        final result = await server.startScreencast();
        expect(result['transport'], equals('tcp'));
        await server.stopScreencast();
      });
    });

    group('Given stopScreencast when not active', () {
      test('When called, Then completes without error', () async {
        final server = createNativeServer();

        // Should not throw.
        await server.stopScreencast();
        expect(server.isActive, isFalse);
      });
    });

    group('Given isActive', () {
      test('When TCP delegate is active, Then isActive reflects active state',
          () async {
        final server = createNativeServer();

        expect(server.isActive, isFalse);

        await server.startScreencast();
        expect(server.isActive, isTrue);

        await server.stopScreencast();
        expect(server.isActive, isFalse);
      });

      test('When WS delegate is active, Then isActive reflects active state',
          () async {
        final wsServer = await FakeWsServer.bind();
        final server = createNativeServer();

        try {
          expect(server.isActive, isFalse);

          await server.startScreencast(wsPort: wsServer.port);
          expect(server.isActive, isTrue);

          await server.stopScreencast();
          expect(server.isActive, isFalse);
        } finally {
          await wsServer.close();
        }
      });
    });
  });
}
