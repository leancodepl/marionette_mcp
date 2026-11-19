import 'dart:async';

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
enum NativePlatform { android, ios }

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

  static const _cancelled = NativeOperationFailedException(
    'Cancelled by a newer native_connect, a native_disconnect or a '
    'server shutdown while the device session was starting.',
  );

  final NativeConnectorFactory _connectorFactory;

  /// Bumped by every [connect] and [dispose], so a connect still waiting for
  /// its connector can tell it was replaced or cancelled.
  var _connectCalls = 0;

  /// Completes when the latest [connect] has finished. The next one waits for
  /// it: two bootstraps on one device share its UIAutomator2 / WDA server, so
  /// a stale connector must be disposed before the next bootstrap starts.
  Future<void> _latestConnect = Future<void>.value();

  /// Logger shared by the native tools.
  final logging.Logger logger;

  /// Active native connector, or null when disconnected.
  NativeConnector? connector;

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
  /// Connects run one at a time: each waits until the one before it has
  /// finished. The active connector is disposed first, so a failed connect
  /// leaves the context disconnected. A newer [connect] or a [dispose] that
  /// starts before the connector is created cancels this call: its connector
  /// is disposed, or never created when the call is still waiting, and it
  /// throws [NativeOperationFailedException].
  Future<NativeConnector> connect(
    NativePlatform platform, {
    String? serial,
    String? udid,
  }) async {
    final call = ++_connectCalls;
    final previous = _latestConnect;
    final finished = Completer<void>();
    _latestConnect = finished.future;
    try {
      await previous;
      await _disposeConnector();
      if (call != _connectCalls) throw _cancelled;
      final created = await _connectorFactory(
        platform,
        serial: serial,
        udid: udid,
      );
      if (call != _connectCalls) {
        await created.dispose();
        throw _cancelled;
      }
      connector = created;
      return created;
    } finally {
      finished.complete();
    }
  }

  /// Returns the active connector or throws [NativeNotConnectedException].
  NativeConnector requireConnector() {
    final active = connector;
    if (active == null) {
      throw const NativeNotConnectedException();
    }
    return active;
  }

  /// Tears down the active connector if any, and cancels a pending
  /// [connect]. Safe to call multiple times.
  Future<void> dispose() async {
    _connectCalls++;
    await _disposeConnector();
  }

  Future<void> _disposeConnector() async {
    final active = connector;
    connector = null;
    if (active != null) {
      await active.dispose();
    }
  }
}
