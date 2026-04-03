import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_mcp/src/video/frame_protocol.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/tcp_frame_reader.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('TcpFrameReader', () {
    late ServerSocket server;
    late int port;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    });

    tearDown(() async {
      await server.close();
    });

    test('reads a single frame from the server', () async {
      final frameBytes = encodeTestFrame(
        width: 4,
        height: 2,
        timestampMs: 100,
        fillByte: 0xAB,
      );

      // Server sends one frame then closes.
      server.listen((socket) {
        socket.add(frameBytes);
        socket.close();
      });

      final reader = TcpFrameReader(host: 'localhost', port: port);
      await reader.connect();

      final frames = await reader.frames.toList();

      expect(frames, hasLength(1));
      expect(frames[0].timestampMs, equals(100));
      expect(frames[0].rgbaBytes.length, equals(4 * 2 * 4));
      expect(frames[0].rgbaBytes[0], equals(0xAB));
    });

    test('reads multiple frames in sequence', () async {
      final frame1 = encodeTestFrame(width: 2, height: 2, timestampMs: 0);
      final frame2 = encodeTestFrame(width: 2, height: 2, timestampMs: 40);
      final frame3 = encodeTestFrame(width: 2, height: 2, timestampMs: 80);

      server.listen((socket) {
        socket.add(frame1);
        socket.add(frame2);
        socket.add(frame3);
        socket.close();
      });

      final reader = TcpFrameReader(host: 'localhost', port: port);
      await reader.connect();

      final frames = await reader.frames.toList();

      expect(frames, hasLength(3));
      expect(frames[0].timestampMs, equals(0));
      expect(frames[1].timestampMs, equals(40));
      expect(frames[2].timestampMs, equals(80));
    });

    test('handles frame split across TCP packets', () async {
      final frameBytes = encodeTestFrame(width: 4, height: 2, timestampMs: 500);

      // Split the frame at an arbitrary point (middle of payload).
      final splitPoint = FrameHeader.byteLength + 10;
      final part1 = frameBytes.sublist(0, splitPoint);
      final part2 = frameBytes.sublist(splitPoint);

      server.listen((socket) async {
        socket.add(part1);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        socket.add(part2);
        await socket.close();
      });

      final reader = TcpFrameReader(host: 'localhost', port: port);
      await reader.connect();

      final frames = await reader.frames.toList();

      expect(frames, hasLength(1));
      expect(frames[0].timestampMs, equals(500));
    });

    test('completes stream when server disconnects', () async {
      server.listen((socket) {
        socket.close();
      });

      final reader = TcpFrameReader(host: 'localhost', port: port);
      await reader.connect();

      final frames = await reader.frames.toList();

      expect(frames, isEmpty);
    });

    test('emits error and closes stream on malformed frame data', () async {
      // Send 20 bytes with an invalid magic number.
      final badHeader = Uint8List(20);
      final view = ByteData.sublistView(badHeader);
      view.setUint32(0, 0xDEADBEEF, Endian.little); // wrong magic
      view.setUint32(4, 16, Endian.little); // frameLength
      view.setUint32(8, 2, Endian.little); // width
      view.setUint32(12, 2, Endian.little); // height
      view.setUint32(16, 100, Endian.little); // timestampMs

      server.listen((socket) {
        socket.add(badHeader);
        socket.close();
      });

      final reader = TcpFrameReader(host: 'localhost', port: port);
      await reader.connect();

      final errors = <Object>[];
      final frames = <SourceFrame>[];
      final done = Completer<void>();
      reader.frames.listen(
        frames.add,
        onError: errors.add,
        onDone: done.complete,
      );
      await done.future;

      expect(errors, hasLength(1));
      expect(errors[0], isA<FormatException>());
      expect(frames, isEmpty);
    });

    test('close cancels the stream', () async {
      // Server sends frames forever.
      server.listen((socket) {
        socket.done.catchError((_) {}); // Ignore client disconnect errors.
        Timer.periodic(const Duration(milliseconds: 10), (timer) {
          try {
            socket.add(encodeTestFrame(width: 2, height: 2, timestampMs: 0));
          } catch (_) {
            timer.cancel();
          }
        });
      });

      final reader = TcpFrameReader(host: 'localhost', port: port);
      await reader.connect();

      final received = <SourceFrame>[];
      final sub = reader.frames.listen(
        received.add,
        onError: (_) {}, // Ignore errors from close
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await reader.close();
      await sub.cancel();

      final countAtClose = received.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // No more frames after close.
      expect(received.length, equals(countAtClose));
      expect(countAtClose, greaterThan(0));
    });
  });
}
