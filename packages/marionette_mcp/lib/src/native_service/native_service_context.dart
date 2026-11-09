import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/tools/connection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/keyboard_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/notification_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/screenshot_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/text_tools.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';

export 'package:marionette_mcp/src/native_service/native_exceptions.dart'
    show NativeNotConnectedException;

/// Platform targeted by a native automation session.
enum NativePlatform {
  android,
  ios;

  /// Parses the `platform` tool argument (case-insensitive), or returns
  /// null for anything else.
  static NativePlatform? tryParse(String? raw) {
    final normalized = raw?.toLowerCase().trim();
    for (final platform in values) {
      if (platform.name == normalized) return platform;
    }
    return null;
  }
}

/// Creates a connected [NativeConnector] for [platform].
///
/// [serial] selects an Android device, [udid] an iOS Simulator; the one not
/// matching [platform] is ignored.
typedef NativeConnectorFactory = Future<NativeConnector> Function(
  NativePlatform platform, {
  String? serial,
  String? udid,
});

Future<NativeConnector> _connectPlatform(
  NativePlatform platform, {
  String? serial,
  String? udid,
}) =>
    switch (platform) {
      NativePlatform.android => AndroidNativeConnector.connect(serial: serial),
      NativePlatform.ios => IosNativeConnector.connect(udid: udid),
    };

/// Context for managing the optional native automation session and
/// registering native MCP tools.
///
/// Independent of [VmServiceContext] — Flutter `connect` and
/// `native_connect` can be used separately or together.
final class NativeServiceContext {
  NativeServiceContext({
    NativeConnectorFactory? connectorFactory,
    logging.Logger? logger,
  })  : _connectorFactory = connectorFactory ?? _connectPlatform,
        logger = logger ?? logging.Logger('NativeServiceContext');

  final NativeConnectorFactory _connectorFactory;

  /// Logger shared by the native tools.
  final logging.Logger logger;

  /// Active native connector, or null when disconnected.
  NativeConnector? connector;

  /// Platform of the active session; null when disconnected.
  NativePlatform? platform;

  /// Registers all native-lane MCP tools with [server].
  ///
  /// Every call is recorded to the active session's steps.md through
  /// [stepLogger] — the one the Flutter lane's `connect` opens a session in,
  /// so both lanes log into the same run.
  void registerTools(McpServer server, {StepLogger? stepLogger}) {
    final loggedServer = LoggedMcpServer(server, stepLogger ?? StepLogger());
    registerNativeConnectionTools(loggedServer, this);
    registerNativeInspectionTools(loggedServer, this);
    registerNativeGestureTools(loggedServer, this);
    registerNativeTextTools(loggedServer, this);
    registerNativeKeyboardTools(loggedServer, this);
    registerNativeScreenshotTools(loggedServer, this);
    registerNativeNotificationTools(loggedServer, this);
  }

  /// Replaces any active session with a new one for [platform].
  ///
  /// The previous connector is disposed first, so a failed connect leaves
  /// the context disconnected.
  Future<NativeConnector> connect(
    NativePlatform platform, {
    String? serial,
    String? udid,
  }) async {
    await dispose();
    final created = await _connectorFactory(
      platform,
      serial: serial,
      udid: udid,
    );
    connector = created;
    this.platform = platform;
    return created;
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
    platform = null;
    if (active != null) {
      await active.dispose();
    }
  }
}
