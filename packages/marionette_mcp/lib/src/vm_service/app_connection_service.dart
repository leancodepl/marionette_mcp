import 'package:logging/logging.dart' as logging;

import '../session/session.dart';
import '../session/session_manager.dart';
import '../version.g.dart' as v;
import 'vm_service_connector.dart';

/// The phase in which an app connection failed.
enum AppConnectionFailureKind { versionMismatch, versionCheck, connection }

/// A connection failure without transport-specific presentation.
final class AppConnectionFailure {
  const AppConnectionFailure(this.kind, {this.cause, this.actualVersion});

  final AppConnectionFailureKind kind;
  final Object? cause;
  final String? actualVersion;
}

/// The outcome of a connection attempt and optional report setup.
final class AppConnectionResult {
  const AppConnectionResult({
    required this.generation,
    required this.uri,
    this.session,
    this.reportWarning,
    this.failure,
  });

  final int generation;
  final String uri;
  final Session? session;
  final Object? reportWarning;
  final AppConnectionFailure? failure;
}

/// The outcome of closing a connection, including its original report session.
final class AppDisconnectionResult {
  const AppDisconnectionResult({this.closingSession, this.error});

  final Session? closingSession;
  final Object? error;
}

/// Owns app connection transitions, version checks, and optional report sessions.
class AppConnectionService {
  AppConnectionService({
    VmServiceConnector? connector,
    SessionManager? sessionManager,
    this.expectedVersion = v.version,
    logging.Logger? logger,
    this.onConnected,
    this.onRetired,
    this.onSessionChanged,
  })  : connector = connector ?? VmServiceConnector(),
        sessionManager = sessionManager ?? SessionManager(),
        logger = logger ?? logging.Logger('AppConnectionService');

  final VmServiceConnector connector;
  final SessionManager sessionManager;
  final String expectedVersion;
  final logging.Logger logger;
  final Future<void> Function()? onConnected;
  final void Function()? onRetired;
  final void Function(Session?)? onSessionChanged;

  bool _disposed = false;
  int _generation = 0;
  Session? _session;

  bool get isDisposed => _disposed;
  Session? get session => _session;

  /// Whether work belongs to the currently active transition.
  bool ownsConnection(int generation) =>
      !_disposed && generation == _generation;

  void _ensureCurrent(int generation) {
    if (!ownsConnection(generation)) {
      throw StateError('The app connection was closed or superseded.');
    }
  }

  void _setSession(Session? session) {
    _session = session;
    onSessionChanged?.call(session);
  }

  /// Connects and performs the binding handshake before opening a report.
  Future<AppConnectionResult> connect({
    required String uri,
    String? sessionTitle,
    String? sessionDir,
  }) async {
    final generation = ++_generation;
    logger.info('Connecting to app at $uri');
    _setSession(null);
    onRetired?.call();
    AppConnectionResult result({
      Session? session,
      Object? reportWarning,
      AppConnectionFailure? failure,
    }) =>
        AppConnectionResult(
          generation: generation,
          uri: uri,
          session: session,
          reportWarning: reportWarning,
          failure: failure,
        );

    try {
      _ensureCurrent(generation);
      await connector.connect(uri);
      _ensureCurrent(generation);
      try {
        final bindingVersion = await connector.getVersion();
        _ensureCurrent(generation);
        if (bindingVersion != expectedVersion) {
          await connector.disconnect();
          _ensureCurrent(generation);
          return result(
            failure: AppConnectionFailure(
              AppConnectionFailureKind.versionMismatch,
              actualVersion: bindingVersion,
            ),
          );
        }
      } catch (err) {
        logger.warning('Failed to check binding version', err);
        if (ownsConnection(generation)) {
          await connector.disconnect();
        }
        return result(
          failure: AppConnectionFailure(
            AppConnectionFailureKind.versionCheck,
            cause: err,
          ),
        );
      }

      await onConnected?.call();
      _ensureCurrent(generation);
      var reportsEnabled = false;
      try {
        reportsEnabled = await connector.getSessionReportsEnabled();
      } catch (err) {
        logger.warning(
          'Failed to read binding configuration; continuing without '
          'session reports',
          err,
        );
      }
      _ensureCurrent(generation);
      if (!reportsEnabled) {
        _setSession(null);
        return result();
      }
      try {
        final session = sessionManager.create(
          title: sessionTitle,
          baseDirOverride: sessionDir,
        );
        _setSession(session);
        return result(session: session);
      } catch (err) {
        logger.warning(
          'Failed to open session directory; continuing without '
          'session reports',
          err,
        );
        _setSession(null);
        return result(reportWarning: err);
      }
    } catch (err) {
      logger.severe('Failed to connect to app', err);
      return result(
        failure: AppConnectionFailure(
          AppConnectionFailureKind.connection,
          cause: err,
        ),
      );
    }
  }

  /// Retires registrations before closing, preserving a newer session.
  Future<AppDisconnectionResult> disconnect() async {
    final generation = ++_generation;
    final closingSession = _session;
    logger.info('Disconnecting from app');
    try {
      onRetired?.call();
      await connector.disconnect();
      if (ownsConnection(generation)) _setSession(null);
      return AppDisconnectionResult(closingSession: closingSession);
    } catch (err) {
      logger.severe('Error during disconnect', err);
      return AppDisconnectionResult(closingSession: closingSession, error: err);
    }
  }

  /// Retires all work and releases the active connection and report.
  Future<void> dispose() async {
    _disposed = true;
    ++_generation;
    onRetired?.call();
    _setSession(null);
    await connector.disconnect();
  }
}
