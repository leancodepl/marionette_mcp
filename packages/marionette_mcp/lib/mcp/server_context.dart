import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/mcp/step_logging.dart';
import 'package:marionette_mcp/src/session/session_manager.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

import 'tools/dynamic_extension_tools.dart';

/// Shared app connection and session state, owned by the server lifecycle.
///
/// Tool metadata and registration live in the MCP composition and tool classes.
final class VmServiceContext {
  VmServiceContext({VmServiceConnector? connector})
      : connector = connector ?? VmServiceConnector();

  final VmServiceConnector connector;
  final logging.Logger logger = logging.Logger('VmServiceContext');
  final SessionManager sessionManager = SessionManager();
  final StepLogger stepLogger = StepLogger();

  DynamicExtensionTools? _dynamicTools;
  bool _disposed = false;
  int _connectionEpoch = 0;

  /// Whether the server owner has retired this context.
  bool get isDisposed => _disposed;

  /// Starts a transition that supersedes older connection/session work.
  int beginTransition() => ++_connectionEpoch;

  /// Whether asynchronous work still belongs to the active connection.
  bool ownsConnection(int epoch) => !_disposed && epoch == _connectionEpoch;

  /// Rejects asynchronous work superseded by another transition or disposal.
  void ensureCurrentConnection(int epoch) {
    if (!ownsConnection(epoch)) {
      throw StateError('The app connection was closed or superseded.');
    }
  }

  /// Gives this context ownership of its app-specific MCP registrations.
  void attachDynamicTools(DynamicExtensionTools tools) {
    if (_disposed || _dynamicTools != null) {
      throw StateError(
          'The context is disposed or already attached to a server.');
    }
    _dynamicTools = tools;
  }

  /// Discovers the connected app's schema-bearing extension tools.
  Future<void> registerDynamicTools() async => _dynamicTools?.registerAll();

  /// Retires all app-specific tools before replacing or closing a connection.
  void removeDynamicTools() => _dynamicTools?.removeAll();

  /// Releases dynamic registrations, reports, and the VM-service connection.
  Future<void> dispose() async {
    _disposed = true;
    ++_connectionEpoch;
    removeDynamicTools();
    stepLogger.session = null;
    await connector.disconnect();
  }
}
