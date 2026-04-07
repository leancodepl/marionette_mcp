import 'dart:typed_data';

import 'package:marionette_mcp/src/video/frame_protocol.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('FrameHeader', () {
    test('encodes to exactly 20 bytes', () {
      final header = FrameHeader(
        frameLength: 1920 * 1080 * 4,
        width: 1920,
        height: 1080,
        timestampMs: 12345,
      );

      final bytes = header.encode();

      expect(bytes.length, equals(FrameHeader.byteLength));
      expect(FrameHeader.byteLength, equals(20));
    });

    test('round-trips through encode and decode', () {
      final original = FrameHeader(
        frameLength: 800 * 600 * 4,
        width: 800,
        height: 600,
        timestampMs: 42000,
      );

      final decoded = FrameHeader.decode(original.encode());

      expect(decoded.frameLength, equals(original.frameLength));
      expect(decoded.width, equals(original.width));
      expect(decoded.height, equals(original.height));
      expect(decoded.timestampMs, equals(original.timestampMs));
    });

    test('encodes magic bytes at offset 0', () {
      final header = FrameHeader(
        frameLength: 100,
        width: 10,
        height: 10,
        timestampMs: 0,
      );

      final bytes = header.encode();
      final view = ByteData.sublistView(bytes);

      expect(view.getUint32(0, Endian.little), equals(FrameHeader.magic));
    });

    test('decode rejects bytes with wrong magic', () {
      final badBytes = Uint8List(20); // all zeros — wrong magic

      expect(
        () => FrameHeader.decode(badBytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode rejects buffer shorter than 20 bytes', () {
      final tooShort = Uint8List(19);

      expect(
        () => FrameHeader.decode(tooShort),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('FrameAssembler', () {
    test('drains a complete frame delivered in one chunk', () {
      final assembler = FrameAssembler();
      assembler.addData(encodeTestFrame(timestampMs: 100));

      final frames = assembler.drain().toList();
      expect(frames, hasLength(1));
      expect(frames[0].header.timestampMs, 100);
      expect(frames[0].rgbaBytes.length, 2 * 2 * 4);
    });

    test('drains multiple frames from one chunk', () {
      final assembler = FrameAssembler();
      final combined = Uint8List.fromList([
        ...encodeTestFrame(timestampMs: 10),
        ...encodeTestFrame(timestampMs: 20),
        ...encodeTestFrame(timestampMs: 30),
      ]);
      assembler.addData(combined);

      final frames = assembler.drain().toList();
      expect(frames.map((f) => f.header.timestampMs), [10, 20, 30]);
    });

    test('reassembles a frame split across two chunks', () {
      final full = encodeTestFrame(timestampMs: 500);
      final split = FrameHeader.byteLength + 4;

      final assembler = FrameAssembler();
      assembler.addData(full.sublist(0, split));
      expect(assembler.drain().toList(), isEmpty);

      assembler.addData(full.sublist(split));
      final frames = assembler.drain().toList();
      expect(frames, hasLength(1));
      expect(frames[0].header.timestampMs, 500);
    });

    test('yields nothing when header is incomplete', () {
      final assembler = FrameAssembler();
      assembler.addData(Uint8List(10)); // Less than 20-byte header.

      expect(assembler.drain().toList(), isEmpty);
    });
  });
}
