import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/session/session_manager.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

/// Base class for commands that operate on a connected Flutter app instance.
///
/// Handles resolving the instance name from the global `--instance` flag,
/// looking up the URI from the registry, connecting, executing, and
/// disconnecting. When the app enables session reports, also opens a fresh
/// session directory, the same kind the MCP server uses, and logs one
/// steps.md line per invocation — CLI parity with the MCP server's
/// per-tool-call logging, since one CLI invocation runs exactly one command.
abstract class InstanceCommand extends Command<int> {
  InstanceRegistry get registry;

  /// Subclasses implement this to perform their operation on a connected
  /// [connector].
  Future<int> execute(VmServiceConnector connector);

  @override
  Future<int> run() async {
    final rawInstance = globalResults?['instance'] as String?;
    final rawUri = globalResults?['uri'] as String?;
    final instanceName =
        (rawInstance != null && rawInstance.isNotEmpty) ? rawInstance : null;
    final directUri = (rawUri != null && rawUri.isNotEmpty) ? rawUri : null;

    if (instanceName != null && directUri != null) {
      usageException(
        '--instance (-i) and --uri are mutually exclusive. Use one or the other.',
      );
    }

    if (instanceName == null && directUri == null) {
      usageException('--instance (-i) or --uri is required for this command.');
    }

    late final String uri;
    late final String displayName;
    final isStateless = directUri != null;

    if (directUri != null) {
      uri = directUri;
      displayName = directUri;
    } else if (instanceName != null) {
      final info = registry.get(instanceName);
      if (info == null) {
        stderr.writeln(
          'Instance "$instanceName" not found. '
          'Use "marionette list" to see registered instances.',
        );
        return 1;
      }
      uri = info.uri;
      displayName = instanceName;
    }

    final rawTimeout = globalResults?['timeout'] as String? ?? '5';
    final timeoutSeconds = int.tryParse(rawTimeout);
    if (timeoutSeconds == null) {
      stderr.writeln('Invalid timeout value: "$rawTimeout"');
      return 64;
    }
    final connector = VmServiceConnector();

    Session? session;
    try {
      await connector.connect(uri).timeout(
            Duration(seconds: timeoutSeconds),
            onTimeout: () => throw TimeoutException(
              'Connection to "$displayName" at $uri timed out '
              'after ${timeoutSeconds}s. Is the app still running?',
            ),
          );

      if (await _sessionReportsEnabled(connector)) {
        try {
          session = SessionManager().create(
            title: globalResults?['session'] as String?,
            baseDirOverride: globalResults?['session-dir'] as String?,
          );
        } catch (e) {
          stderr.writeln('Could not open a session directory: $e');
          return 1;
        }
      }

      final exitCode = await execute(connector);
      _logStep(session,
          outcome: exitCode == 0 ? 'ok' : 'error: exit $exitCode');
      return exitCode;
    } on SocketException catch (e) {
      final hint = isStateless
          ? 'Check the URI and ensure the app is still running.'
          : 'The app may have stopped. '
              'Try "marionette doctor" or "marionette unregister $displayName".';
      stderr.writeln('Could not connect to "$displayName" at $uri: $e\n$hint');
      _logStep(session, outcome: describeStepError(e.toString()));
      return 1;
    } on TimeoutException catch (e) {
      stderr.writeln(e.message);
      _logStep(session, outcome: describeStepError(e.message ?? 'timed out'));
      return 1;
    } catch (e) {
      stderr.writeln('Error: $e');
      _logStep(session, outcome: describeStepError(e.toString()));
      return 1;
    } finally {
      await connector.disconnect();
    }
  }

  /// Whether the app opted into session reports
  /// (`MarionetteConfiguration.enableSessionReports`). Treated as off when
  /// the binding can't answer — the CLI doesn't enforce a version match, so
  /// an older binding without `marionette.getConfiguration` must still work.
  Future<bool> _sessionReportsEnabled(VmServiceConnector connector) async {
    try {
      return await connector.getSessionReportsEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Appends this invocation's steps.md line: the command name, a selector
  /// summary built from whichever options the user actually passed, and
  /// [outcome]. Mirrors the MCP server's step logging (see [StepLogger]) so
  /// a session started via one transport reads the same way from the other.
  /// No-op when [session] is null, i.e. session reports are disabled or the
  /// connection failed before the app's configuration could be read.
  void _logStep(Session? session, {required String outcome}) {
    if (session == null) return;
    final args = <String, dynamic>{
      for (final option in argResults?.options ?? const <String>[])
        if (argResults!.wasParsed(option)) option: argResults![option],
    };
    final selector = describeStepSelector(name, args);
    final line = formatStepLine(name, selector, outcome);
    session.stepsFile.writeAsStringSync('$line\n', mode: FileMode.append);
  }
}
