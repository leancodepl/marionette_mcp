import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/frame_protocol.dart';
import 'package:marionette_flutter/src/services/screencast_tcp_server.dart';

import 'screencast_test_helpers.dart';

/// Creates a [ScreencastTcpServer] with a fake service and viewport provider.
/// Tests use [test()] (not [testWidgets]) because real TCP I/O is incompatible
/// with the FakeAsync zone that [testWidgets] creates.
ScreencastTcpServer createServer({
  FakeScreencastService? service,
  Size viewportSize = const Size(800, 600),
  void Function(Size? maxSize)? onFactoryCall,
}) {
  return ScreencastTcpServer(
    screencastServiceFactory: ({Size? maxSize}) {
      onFactoryCall?.call(maxSize);
      return service ?? FakeScreencastService();
    },
    viewportSizeProvider: () => viewportSize,
  );
}

void main() {
  group('ScreencastTcpServer', () {
    group('Given startScreencast is called', () {
      test('When called, Then returns port, viewportWidth, and viewportHeight',
          () async {
        final server = createServer();

        final result = await server.startScreencast();

        expect(result['transport'], equals('tcp'));
        expect(result['port'], isA<int>());
        expect((result['port'] as int), greaterThan(0));
        expect(result['viewportWidth'], equals(800));
        expect(result['viewportHeight'], equals(600));

        await server.stopScreencast();
      });

      test('When called twice, Then second call throws StateError', () async {
        final server = createServer();

        await server.startScreencast();

        expect(
          () => server.startScreencast(),
          throwsStateError,
        );

        await server.stopScreencast();
      });
    });

    group('Given a connected TCP client', () {
      test(
          'When a frame is delivered, Then client receives MRNT header + RGBA payload',
          () async {
        final service = FakeScreencastService();
        final server = createServer(service: service);

        final result = await server.startScreencast();
        final port = result['port'] as int;

        // Connect a TCP client.
        final client = await Socket.connect('localhost', port);

        try {
          // Give the server a moment to accept the connection.
          await Future<void>.delayed(const Duration(milliseconds: 50));

          // Deliver a frame.
          const frameWidth = 4;
          const frameHeight = 2;
          await service.deliverFrame(fakeFrame(
            timestampMs: 500,
            width: frameWidth,
            height: frameHeight,
          ));

          // Collect data then stop the server (which closes connections).
          final receivedData = <int>[];
          final subscription = client.listen((data) {
            receivedData.addAll(data);
          });

          // Wait for data to arrive, then stop.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await server.stopScreencast();
          await subscription.cancel();

          // Verify MRNT header.
          expect(receivedData.length,
              greaterThanOrEqualTo(FrameHeader.byteLength));
          final headerBytes = Uint8List.fromList(
              receivedData.sublist(0, FrameHeader.byteLength));
          final header = FrameHeader.decode(headerBytes);

          expect(header.width, equals(frameWidth));
          expect(header.height, equals(frameHeight));
          expect(header.timestampMs, equals(500));
          expect(header.frameLength, equals(frameWidth * frameHeight * 4));

          // Verify payload.
          final totalExpected =
              FrameHeader.byteLength + frameWidth * frameHeight * 4;
          expect(receivedData.length, equals(totalExpected));
        } finally {
          client.destroy();
        }
      });
    });

    group('Given stopScreencast is called', () {
      test('When active, Then stops and sets isActive to false', () async {
        final server = createServer();

        await server.startScreencast();
        expect(server.isActive, isTrue);

        await server.stopScreencast();
        expect(server.isActive, isFalse);
      });

      test('When called without starting, Then completes without error',
          () async {
        final server = createServer();

        // Should not throw.
        await server.stopScreencast();
        expect(server.isActive, isFalse);
      });
    });

    group('Given startScreencast with params', () {
      test(
          'When maxWidth and maxHeight provided, Then service is created with maxSize',
          () async {
        Size? capturedMaxSize;
        final server = createServer(
          onFactoryCall: (maxSize) => capturedMaxSize = maxSize,
        );

        await server.startScreencast(
          maxWidth: 400,
          maxHeight: 300,
        );

        expect(capturedMaxSize, equals(const Size(400, 300)));

        await server.stopScreencast();
      });
    });

    group('Given non-integer viewport dimensions', () {
      test(
          'When viewport is 800.3x600.7, Then viewportWidth/Height use round()',
          () async {
        final server = createServer(viewportSize: const Size(800.3, 600.7));

        final result = await server.startScreencast();

        expect(result['viewportWidth'], equals(800));
        expect(result['viewportHeight'], equals(601));

        await server.stopScreencast();
      });
    });
  });
}
