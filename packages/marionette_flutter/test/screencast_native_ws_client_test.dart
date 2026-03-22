import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/frame_protocol.dart';
import 'package:marionette_flutter/src/services/screencast_native_ws_client.dart';

import 'screencast_test_helpers.dart';

// ---------------------------------------------------------------------------
// Factory helper
// ---------------------------------------------------------------------------

ScreencastNativeWsClient createClient({
  FakeScreencastService? service,
  Size viewportSize = const Size(800, 600),
  void Function(Size? maxSize)? onFactoryCall,
}) {
  return ScreencastNativeWsClient(
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
  group('ScreencastNativeWsClient', () {
    group('Given startScreencast(wsPort) is called and server is listening',
        () {
      test(
          'When a frame is delivered, Then server receives MRNT header + RGBA payload',
          () async {
        final wsServer = await FakeWsServer.bind();
        final service = FakeScreencastService();
        final client = createClient(service: service);

        try {
          await client.startScreencast(wsPort: wsServer.port);

          // Give the client time to establish the WebSocket connection.
          await Future<void>.delayed(const Duration(milliseconds: 50));

          const frameWidth = 4;
          const frameHeight = 2;
          await service.deliverFrame(fakeFrame(
            timestampMs: 500,
            width: frameWidth,
            height: frameHeight,
          ));

          // Wait for data to arrive at the server.
          await Future<void>.delayed(const Duration(milliseconds: 200));

          // Should have received at least one binary WebSocket message.
          expect(wsServer.receivedMessages, isNotEmpty);

          // Collect all received bytes.
          final allBytes = <int>[];
          for (final msg in wsServer.receivedMessages) {
            allBytes.addAll(msg);
          }

          // Verify MRNT header is present.
          expect(allBytes.length, greaterThanOrEqualTo(FrameHeader.byteLength));
          final headerBytes =
              Uint8List.fromList(allBytes.sublist(0, FrameHeader.byteLength));
          final header = FrameHeader.decode(headerBytes);

          // Verify magic bytes from raw data.
          final view = ByteData.sublistView(headerBytes);
          final magicBytes = view.getUint32(0, Endian.little);
          expect(magicBytes, equals(FrameHeader.magic));

          expect(header.width, equals(frameWidth));
          expect(header.height, equals(frameHeight));
          expect(header.timestampMs, equals(500));
          expect(header.frameLength, equals(frameWidth * frameHeight * 4));

          // Verify total bytes = header + payload.
          final totalExpected =
              FrameHeader.byteLength + frameWidth * frameHeight * 4;
          expect(allBytes.length, equals(totalExpected));
        } finally {
          await client.stopScreencast();
          await wsServer.close();
        }
      });

      test(
          'When startScreencast returns, Then result contains correct transport, viewport, and frame dimensions',
          () async {
        final wsServer = await FakeWsServer.bind();
        final client = createClient(viewportSize: const Size(1080, 1920));

        try {
          final result = await client.startScreencast(wsPort: wsServer.port);

          expect(result['transport'], equals('ws'));
          expect(result['viewportWidth'], equals(1080));
          expect(result['viewportHeight'], equals(1920));
          expect(result['frameWidth'], isA<int>());
          expect(result['frameHeight'], isA<int>());
          expect((result['frameWidth'] as int), greaterThan(0));
          expect((result['frameHeight'] as int), greaterThan(0));
        } finally {
          await client.stopScreencast();
          await wsServer.close();
        }
      });
    });

    group('Given stopScreencast is called', () {
      test(
          'When active, Then closes WebSocket connection and isActive is false',
          () async {
        final wsServer = await FakeWsServer.bind();

        // Track when the WS connection closes on the server side.
        final connectionClosed = Completer<void>();
        // Re-bind a new server that tracks close events.
        await wsServer.close();

        // Use a fresh server that watches for connection close.
        final httpServer =
            await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final wsPort = httpServer.port;
        httpServer.listen((request) async {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            final ws = await WebSocketTransformer.upgrade(request);
            ws.listen(
              null,
              onDone: () {
                if (!connectionClosed.isCompleted) {
                  connectionClosed.complete();
                }
              },
            );
          }
        });

        final client = createClient();

        try {
          await client.startScreencast(wsPort: wsPort);
          expect(client.isActive, isTrue);

          await client.stopScreencast();

          expect(client.isActive, isFalse);

          // The server should observe the connection close within 2 seconds.
          await connectionClosed.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail(
              'WebSocket connection was not closed after stopScreencast()',
            ),
          );
        } finally {
          await httpServer.close(force: true);
        }
      });

      test('When called without starting, Then completes without error',
          () async {
        final client = createClient();

        // Should not throw.
        await client.stopScreencast();
        expect(client.isActive, isFalse);
      });
    });

    group('Given startScreencast lifecycle', () {
      test(
          'When called without prior connection and then with wsPort, Then lifecycle proceeds correctly',
          () async {
        final wsServer = await FakeWsServer.bind();
        final client = createClient();

        try {
          // Verify not active before start.
          expect(client.isActive, isFalse);

          // Start with wsPort.
          final result = await client.startScreencast(wsPort: wsServer.port);

          expect(client.isActive, isTrue);
          expect(result['transport'], equals('ws'));

          // Stop and verify cleanup.
          await client.stopScreencast();
          expect(client.isActive, isFalse);

          // Can be restarted.
          final result2 = await client.startScreencast(wsPort: wsServer.port);
          expect(client.isActive, isTrue);
          expect(result2['transport'], equals('ws'));
        } finally {
          await client.stopScreencast();
          await wsServer.close();
        }
      });
    });

    group('Given no server is listening', () {
      test(
          'When startScreencast(wsPort) is called, Then throws within 5 seconds',
          () async {
        // Bind a server to get a free port, then close it immediately so
        // nothing is listening on that port.
        final tempServer =
            await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final unusedPort = tempServer.port;
        await tempServer.close(force: true);

        // Give OS time to fully release the port.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final client = createClient();

        await expectLater(
          () => client
              .startScreencast(wsPort: unusedPort)
              .timeout(const Duration(seconds: 5)),
          throwsA(isA<Exception>()),
        );
      });
    });
  });
}
