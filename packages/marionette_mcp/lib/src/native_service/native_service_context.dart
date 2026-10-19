import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/recovering_native_connector.dart';
import 'package:marionette_mcp/src/native_service/tools/bridge_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/connection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/device_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/keyboard_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/screenshot_tools.dart';
import 'package:marionette_mcp/src/native_service/tools/text_tools.dart';
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
    this.flutterViewMetrics,
    logging.Logger? logger,
  })  : _connectorFactory = connectorFactory ?? _connectPlatform,
        logger = logger ?? logging.Logger('NativeServiceContext');

  /// Reads the Flutter view metrics from the Flutter lane
  /// (`marionette.getViewMetrics`), for tools that bridge both lanes
  /// (docs/native-lane-decisions.md#d13). Null when the Flutter lane is not
  /// available in this server.
  final Future<Map<String, dynamic>> Function()? flutterViewMetrics;

  final NativeConnectorFactory _connectorFactory;

  /// Logger shared by the native tools.
  final logging.Logger logger;

  /// Active native connector, or null when disconnected.
  NativeConnector? connector;

  /// Platform of the active session; null when disconnected.
  NativePlatform? platform;

  /// App the device shortcuts act on when no `appId` is given: the first
  /// foreground app of the session that is not a system app
  /// (docs/native-lane-decisions.md#d7).
  String? defaultAppId;

  /// Remembers [foregroundApp] as [defaultAppId] if none is known yet and
  /// it is not a system app.
  void observeForegroundApp(String? foregroundApp) {
    if (defaultAppId != null || foregroundApp == null) return;
    if (isSystemAppId(foregroundApp)) return;
    defaultAppId = foregroundApp;
  }

  /// Reads the foreground app into [defaultAppId] while it is unknown.
  /// Best-effort and free once the default is known.
  Future<void> observeForegroundAppIfUnknown() async {
    final active = connector;
    if (defaultAppId != null || active == null) return;
    try {
      observeForegroundApp(await active.foregroundApp);
    } catch (_) {
      // Only a default for later shortcuts.
    }
  }

  /// [appId] when given, else [defaultAppId] (looking at the foreground app
  /// first while it is unknown); throws when neither is known. An explicit
  /// non-system [appId] also becomes the default when none is known yet —
  /// the agent named the app under test.
  Future<String> resolveAppId(String? appId) async {
    if (appId != null && appId.isNotEmpty) {
      observeForegroundApp(appId);
      return appId;
    }
    await observeForegroundAppIfUnknown();
    return defaultAppId ??
        (throw const NativeOperationFailedException(
          'No appId given and the app under test is not known yet (no '
          'non-system app has been in the foreground in this session).',
          hint: 'Pass appId (Android package name / iOS bundle id), or bring '
              'the app to the front and call native_get_elements once.',
        ));
  }

  /// Registers all native-lane MCP tools with [server].
  void registerTools(McpServer server) {
    registerNativeConnectionTools(server, this);
    registerNativeInspectionTools(server, this);
    registerNativeGestureTools(server, this);
    registerNativeTextTools(server, this);
    registerNativeKeyboardTools(server, this);
    registerNativeScreenshotTools(server, this);
    registerNativeDeviceTools(server, this);
    registerNativeBridgeTools(server, this);
  }

  /// Replaces any active session with a new one for [platform].
  ///
  /// The previous connector is disposed first, so a failed connect leaves
  /// the context disconnected. The new connector is wrapped in a
  /// [RecoveringNativeConnector] that re-establishes a lost session with the
  /// same arguments (see docs/native-lane-decisions.md#d3).
  Future<NativeConnector> connect(
    NativePlatform platform, {
    String? serial,
    String? udid,
  }) async {
    await dispose();
    Future<NativeConnector> create() =>
        _connectorFactory(platform, serial: serial, udid: udid);

    final initial = await create();
    late final RecoveringNativeConnector recovering;
    recovering = RecoveringNativeConnector(
      initial,
      reconnect: create,
      logger: logger,
      onClosed: () {
        if (identical(connector, recovering)) connector = null;
      },
    );
    connector = recovering;
    this.platform = platform;
    try {
      observeForegroundApp(await recovering.foregroundApp);
    } catch (_) {
      // Only a default for later shortcuts; never fail the connect.
    }
    return recovering;
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
    defaultAppId = null;
    if (active != null) {
      await active.dispose();
    }
  }
}
