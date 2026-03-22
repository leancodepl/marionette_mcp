import 'dart:typed_data';

/// A decoded MRNT frame (header + payload).
class DecodedFrame {
  const DecodedFrame({required this.header, required this.rgbaBytes});

  final FrameHeader header;
  final Uint8List rgbaBytes;
}

/// Reassembles MRNT-framed binary data from a byte stream.
///
/// Handles partial delivery — data may arrive in chunks smaller or larger
/// than a single frame. Call [addData] for each chunk and [drain] to
/// yield fully assembled frames.
class FrameAssembler {
  final _buffer = BytesBuilder(copy: false);
  int _bufferedBytes = 0;
  FrameHeader? _pendingHeader;

  /// Appends raw bytes to the internal buffer.
  void addData(List<int> data) {
    _buffer.add(data);
    _bufferedBytes += data.length;
  }

  /// Yields all complete frames currently in the buffer.
  Iterable<DecodedFrame> drain() sync* {
    while (true) {
      if (_pendingHeader == null) {
        if (_bufferedBytes < FrameHeader.byteLength) return;
        final accumulated = _buffer.takeBytes();
        _bufferedBytes = 0;
        _pendingHeader = FrameHeader.decode(
          Uint8List.sublistView(accumulated, 0, FrameHeader.byteLength),
        );
        if (accumulated.length > FrameHeader.byteLength) {
          final remainder = accumulated.sublist(FrameHeader.byteLength);
          _buffer.add(remainder);
          _bufferedBytes = remainder.length;
        }
      }

      final header = _pendingHeader!;
      if (_bufferedBytes < header.frameLength) return;

      final accumulated = _buffer.takeBytes();
      _bufferedBytes = 0;
      final payload = accumulated.sublist(0, header.frameLength);

      yield DecodedFrame(header: header, rgbaBytes: payload);

      _pendingHeader = null;
      if (accumulated.length > header.frameLength) {
        final remainder = accumulated.sublist(header.frameLength);
        _buffer.add(remainder);
        _bufferedBytes = remainder.length;
      }
    }
  }
}

/// Binary frame header for the TCP screencast protocol.
///
/// Wire format (20 bytes, little-endian):
///   [0..3]   uint32  magic (0x4D524E54 = "MRNT")
///   [4..7]   uint32  frameLength (RGBA payload byte count)
///   [8..11]  uint32  width
///   [12..15] uint32  height
///   [16..19] uint32  timestampMs (elapsed ms since screencast start)
///
/// Keep FrameHeader in sync with marionette_flutter's frame_protocol.dart.
class FrameHeader {
  const FrameHeader({
    required this.frameLength,
    required this.width,
    required this.height,
    required this.timestampMs,
  });

  /// Magic bytes: ASCII "MRNT" as a little-endian uint32.
  static const int magic = 0x4D524E54;

  /// Total header size in bytes.
  static const int byteLength = 20;

  final int frameLength;
  final int width;
  final int height;
  final int timestampMs;

  /// Serializes this header to a 20-byte buffer.
  Uint8List encode() {
    final bytes = Uint8List(byteLength);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, magic, Endian.little);
    view.setUint32(4, frameLength, Endian.little);
    view.setUint32(8, width, Endian.little);
    view.setUint32(12, height, Endian.little);
    view.setUint32(16, timestampMs, Endian.little);
    return bytes;
  }

  /// Deserializes a header from a 20-byte buffer.
  ///
  /// Throws [FormatException] if the buffer is too short or the magic
  /// bytes don't match.
  factory FrameHeader.decode(Uint8List bytes) {
    if (bytes.length < byteLength) {
      throw FormatException(
        'Frame header too short: ${bytes.length} bytes (expected $byteLength)',
      );
    }
    final view = ByteData.sublistView(bytes);
    final m = view.getUint32(0, Endian.little);
    if (m != magic) {
      throw FormatException(
        'Invalid frame magic: 0x${m.toRadixString(16)} '
        '(expected 0x${magic.toRadixString(16)})',
      );
    }
    return FrameHeader(
      frameLength: view.getUint32(4, Endian.little),
      width: view.getUint32(8, Endian.little),
      height: view.getUint32(12, Endian.little),
      timestampMs: view.getUint32(16, Endian.little),
    );
  }
}
