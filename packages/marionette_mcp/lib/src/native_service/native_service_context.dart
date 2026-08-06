import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/tools/connection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/screenshot_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/text_tools.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Exception thrown when a native tool is used without an active
/// [NativeConnector] session.
class NativeNotConnectedException implements Exception {
  const NativeNotConnectedException();

  @override
  String toString() =>
      'Not connected to any native connector. Use native_connect first '
      'with platform (android|ios).';
}

/// Context for managing the optional native automation session and
/// registering native MCP tools.
///
/// Independent of [VmServiceContext] — Flutter `connect` and
/// `native_connect` can be used separately or together.
final class NativeServiceContext {
  NativeServiceContext() : _logger = logging.Logger('NativeServiceContext');

  /// Active native connector, or null when disconnected.
  NativeConnector? connector;

  final logging.Logger _logger;

  /// Registers all native-lane MCP tools with [server].
  void registerTools(McpServer server) {
    registerNativeConnectionTools(server, this, _logger);
    registerNativeInspectionTools(server, this, _logger);
    registerNativeGestureTools(server, this, _logger);
    registerNativeTextTools(server, this, _logger);
    registerNativeScreenshotTools(server, this, _logger);
  }

  /// Returns the active connector or throws [NativeNotConnectedException].
  NativeConnector requireConnector() {
    final active = connector;
    if (active == null) {
      throw const NativeNotConnectedException();
    }
    return active;
  }

  /// Tears down the active connector if any. Safe to call multiple times.
  Future<void> dispose() async {
    final active = connector;
    connector = null;
    if (active != null) {
      await active.dispose();
    }
  }
}
