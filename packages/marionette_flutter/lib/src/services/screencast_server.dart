import 'dart:ui';

import 'package:marionette_flutter/src/services/screencast_service.dart';

/// Factory for creating ScreencastService instances.
typedef ScreencastServiceFactory = ScreencastService Function({
  Size? maxSize,
});

/// Provider for the current viewport size.
typedef ViewportSizeProvider = Size Function();

/// Abstract interface for screencast server implementations.
///
/// Implementations manage the screencast lifecycle and push frames to a
/// consumer over a transport-specific channel (TCP, WebSocket, etc.).
abstract class ScreencastServer {
  /// Whether the screencast is currently active.
  bool get isActive;

  /// Starts the screencast and returns transport-specific connection info.
  ///
  /// The returned map always includes `viewportWidth`, `viewportHeight`,
  /// and `transport`. Additional fields depend on the transport type.
  ///
  /// [wsPort] is used by WebSocket-based implementations (web and native
  /// reverse-WS) — the MCP side passes its WebSocket server port so the
  /// Flutter app can connect back to it.
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  });

  /// Stops the screencast and cleans up resources.
  Future<void> stopScreencast();
}
