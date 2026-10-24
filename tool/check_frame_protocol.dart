import 'dart:typed_data';

import '../packages/marionette_flutter/lib/src/services/frame_protocol.dart'
    as producer;
import '../packages/marionette_mcp/lib/src/video/frame_protocol.dart'
    as consumer;

// Exercise both production implementations without coupling their packages.
void main() {
  _check(producer.FrameHeader.byteLength == 20, 'Producer header length');
  _check(consumer.FrameHeader.byteLength == 20, 'Consumer header length');
  _check(producer.FrameHeader.magic == 0x4D524E54, 'Producer magic');
  _check(consumer.FrameHeader.magic == 0x4D524E54, 'Consumer magic');

  const endianHeader = producer.FrameHeader(
    frameLength: 0x01020304,
    width: 0x05060708,
    height: 0x090A0B0C,
    timestampMs: 0x0D0E0F10,
  );
  _checkBytes(
      endianHeader.encode(),
      [
        0x54,
        0x4E,
        0x52,
        0x4D,
        0x04,
        0x03,
        0x02,
        0x01,
        0x08,
        0x07,
        0x06,
        0x05,
        0x0C,
        0x0B,
        0x0A,
        0x09,
        0x10,
        0x0F,
        0x0E,
        0x0D,
      ],
      'Little-endian wire bytes');

  for (final value in [0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]) {
    final header = producer.FrameHeader(
      frameLength: value,
      width: value,
      height: value,
      timestampMs: value,
    );
    _checkHeader(consumer.FrameHeader.decode(header.encode()), header);
  }

  final fixtures = [
    _Fixture(0, 0, 0),
    _Fixture(1, 1, 1),
    _Fixture(2, 3, 0x80000000),
    _Fixture(256, 1, 0xFFFFFFFF),
  ];
  final stream = BytesBuilder();
  for (final fixture in fixtures) {
    final encoded = fixture.header.encodeWithPayload(fixture.payload);
    _check(
      encoded.length == 20 + fixture.payload.length,
      'Encoded frame length',
    );
    _checkBytes(
      encoded.sublist(0, 20),
      fixture.header.encode(),
      'Combined frame header',
    );
    _checkBytes(encoded.sublist(20), fixture.payload, 'Combined frame payload');
    stream.add(encoded);
  }
  final bytes = stream.takeBytes();
  // Cover single-byte delivery, header/payload boundaries, and coalesced frames.
  for (final chunkSizes in [
    [1],
    [19, 1, 3, 20, 7],
    [20, 4, 21, 23],
    [bytes.length],
  ]) {
    final assembler = consumer.FrameAssembler();
    var offset = 0;
    var chunkIndex = 0;
    var frameIndex = 0;
    while (offset < bytes.length) {
      final requestedEnd = offset + chunkSizes[chunkIndex % chunkSizes.length];
      final end = requestedEnd < bytes.length ? requestedEnd : bytes.length;
      assembler.addData(Uint8List.sublistView(bytes, offset, end));
      offset = end;
      chunkIndex++;
      for (final frame in assembler.drain()) {
        _check(frameIndex < fixtures.length, 'Unexpected extra frame');
        final fixture = fixtures[frameIndex++];
        _checkHeader(frame.header, fixture.header);
        _checkBytes(frame.rgbaBytes, fixture.payload, 'Assembled RGBA payload');
      }
    }
    _check(frameIndex == fixtures.length, 'Missing assembled frames');
    _check(assembler.drain().isEmpty, 'Unexpected trailing frame');
  }
  print('Frame protocol verified: header boundaries and 4 fragmented streams.');
}

class _Fixture {
  _Fixture(int width, int height, int timestampMs)
      : payload = Uint8List.fromList(
          List.generate(width * height * 4, (index) => (index * 31 + 7) & 0xFF),
        ),
        header = producer.FrameHeader(
          frameLength: width * height * 4,
          width: width,
          height: height,
          timestampMs: timestampMs,
        );

  final producer.FrameHeader header;
  final Uint8List payload;
}

void _checkHeader(consumer.FrameHeader actual, producer.FrameHeader expected) {
  _check(actual.frameLength == expected.frameLength, 'Header frameLength');
  _check(actual.width == expected.width, 'Header width');
  _check(actual.height == expected.height, 'Header height');
  _check(actual.timestampMs == expected.timestampMs, 'Header timestampMs');
}

void _checkBytes(List<int> actual, List<int> expected, String label) {
  _check(actual.length == expected.length, '$label length');
  for (var index = 0; index < expected.length; index++) {
    _check(actual[index] == expected[index], '$label at byte $index');
  }
}

void _check(bool condition, String label) {
  if (!condition) throw StateError('Frame protocol mismatch: $label');
}
