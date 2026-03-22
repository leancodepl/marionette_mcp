import 'dart:async';
import 'dart:io';

import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/ws_frame_server.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('WebSocketFrameServer', () {
    group('Given a bound server', () {
      test('When bind is called, Then port is assigned', () async {
        final server = await WebSocketFrameServer.bind();
        expect(server.port, greaterThan(0));
        await server.close();
      });

      test('When a WebSocket client connects and sends an MRNT frame, '
          'Then frames stream emits a SourceFrame', () async {
        final server = await WebSocketFrameServer.bind();
        final ws = await WebSocket.connect('ws://localhost:${server.port}');

        final message = encodeTestFrame(width: 4, height: 2, timestampMs: 500);
        ws.add(message);

        final frame = await server.frames.first;

        expect(frame, isA<SourceFrame>());
        expect(frame.timestampMs, equals(500));
        expect(frame.rgbaBytes.length, equals(4 * 2 * 4));

        await ws.close();
        await server.close();
      });

      test('When multiple frames are sent, '
          'Then all are emitted in order', () async {
        final server = await WebSocketFrameServer.bind();
        final ws = await WebSocket.connect('ws://localhost:${server.port}');

        ws.add(encodeTestFrame(timestampMs: 100));
        ws.add(encodeTestFrame(timestampMs: 200));
        ws.add(encodeTestFrame(timestampMs: 300));

        final frames = await server.frames.take(3).toList();

        expect(frames.map((f) => f.timestampMs), equals([100, 200, 300]));

        await ws.close();
        await server.close();
      });

      test('When the WebSocket client disconnects, '
          'Then the frames stream closes', () async {
        final server = await WebSocketFrameServer.bind();
        final ws = await WebSocket.connect('ws://localhost:${server.port}');

        // Collect all frames into a list (subscribes once).
        final framesFuture = server.frames.toList();

        ws.add(encodeTestFrame(timestampMs: 100));

        // Give time for the frame to be processed, then close the client.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await ws.close();

        // The stream should complete once the client disconnects.
        final frames = await framesFuture;
        expect(frames, hasLength(1));
        expect(frames.first.timestampMs, equals(100));

        await server.close();
      });
    });

    group('Given close is called', () {
      test(
        'When server is closed before client sends, Then frames stream completes empty',
        () async {
          final server = await WebSocketFrameServer.bind();

          // Subscribe before closing so we can await completion.
          final framesFuture = server.frames.toList();

          await server.close();

          final frames = await framesFuture;
          expect(frames, isEmpty);
        },
      );
    });

    group('Given a specific port', () {
      test(
        'When constructed with port and started, Then binds to that port',
        () async {
          // Find a free port first.
          final tempServer = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          final port = tempServer.port;
          await tempServer.close();

          final server = WebSocketFrameServer(port: port);
          await server.start();

          final ws = await WebSocket.connect('ws://localhost:$port');
          ws.add(encodeTestFrame(timestampMs: 42));

          final frame = await server.frames.first;
          expect(frame.timestampMs, equals(42));

          await ws.close();
          await server.close();
        },
      );
    });
  });
}
