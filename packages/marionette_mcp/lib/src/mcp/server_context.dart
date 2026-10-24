import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/step_logging.dart';
import 'package:marionette_mcp/src/vm_service/app_connection_service.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

import 'tools/dynamic_extension_tools.dart';

/// Bridges the app runtime to MCP registrations and session step logging.
final class VmServiceContext {
  VmServiceContext({VmServiceConnector? connector}) {
    connection = AppConnectionService(
      connector: connector,
      logger: logger,
      onConnected: () async => _dynamicTools?.registerAll(),
      onRetired: () => _dynamicTools?.removeAll(),
      onSessionChanged: (session) => stepLogger.session = session,
    );
  }

  late final AppConnectionService connection;
  VmServiceConnector get connector => connection.connector;
  final logging.Logger logger = logging.Logger('VmServiceContext');
  final StepLogger stepLogger = StepLogger();

  DynamicExtensionTools? _dynamicTools;

  /// Whether the server owner has retired this context.
  bool get isDisposed => connection.isDisposed;

  /// Gives this context ownership of its app-specific MCP registrations.
  void attachDynamicTools(DynamicExtensionTools tools) {
    if (isDisposed || _dynamicTools != null) {
      throw StateError(
          'The context is disposed or already attached to a server.');
    }
    _dynamicTools = tools;
  }

  /// Releases dynamic registrations, reports, and the VM-service connection.
  Future<void> dispose() => connection.dispose();
}
