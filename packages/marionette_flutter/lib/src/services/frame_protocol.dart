import 'dart:typed_data';

/// Binary frame header for the TCP screencast protocol.
///
/// Wire format (20 bytes, little-endian):
///   [0..3]   uint32  magic (0x4D524E54 = "MRNT")
///   [4..7]   uint32  frameLength (RGBA payload byte count)
///   [8..11]  uint32  width
///   [12..15] uint32  height
///   [16..19] uint32  timestampMs (elapsed ms since screencast start)
///
/// Keep FrameHeader in sync with marionette_mcp's frame_protocol.dart.
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

  /// Serializes this header followed by [payload] into a single buffer.
  ///
  /// Combining header + payload into one write halves syscall overhead and
  /// avoids header/payload arriving in separate TCP segments or WS frames.
  Uint8List encodeWithPayload(Uint8List payload) {
    final headerBytes = encode();
    final message = Uint8List(headerBytes.length + payload.length);
    message.setAll(0, headerBytes);
    message.setAll(headerBytes.length, payload);
    return message;
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
