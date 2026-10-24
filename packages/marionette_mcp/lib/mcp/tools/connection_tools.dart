import 'package:marionette_mcp/mcp/step_logging.dart';
import 'package:marionette_mcp/src/version.g.dart' as v;
import 'package:mcp_dart/mcp_dart.dart';

import '../server_context.dart';
import 'base_tool.dart';

/// Connection tools log their own session transitions instead of using the
/// ordinary invocation wrapper, which captures the session before execution.
abstract class ConnectionTool extends BaseTool {
  ConnectionTool(this.context);

  final VmServiceContext context;
}

/// Connects an app and opens its optional report session.
class ConnectTool extends ConnectionTool {
  ConnectTool(super.context);

  @override
  String get name => 'connect';

  @override
  String get description =>
      'Connects to a Flutter app via its VM service URI. This must be called before using any other tools. The VM service URI is typically in the format ws://127.0.0.1:PORT/ws and can be found in the Flutter app output when running in debug mode. If the app enabled session reports (MarionetteConfiguration.enableSessionReports), this also opens a fresh session directory under .marionette/sessions/ where the step log and screenshots for this run are kept.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Connect to App');

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'uri': JsonSchema.string(
            description:
                'VM service URI (e.g., ws://127.0.0.1:8181/ws). This is printed in the Flutter app console when running in debug mode.',
          ),
          'session_title': JsonSchema.string(
            description:
                'A short title for this run, e.g. "profile validation". '
                'Keep it under ~60 characters — longer is truncated. '
                'Ignored unless the app enabled session reports. '
                'Slugified and timestamped into the session directory '
                'name. Purely a human-readable label — every connect '
                'opens its own fresh session directory, even if this '
                'matches an earlier title. Falls back to "run-<timestamp>" '
                'when omitted.',
          ),
          'session_dir': JsonSchema.string(
            description:
                'Base directory .marionette/sessions/ is created under. '
                'Overrides the MARIONETTE_SESSION_DIR environment variable. '
                'Only needed when the MCP client hasn\'t set that variable '
                'and the process\'s working directory isn\'t the project root.',
          ),
        },
        required: ['uri'],
      );

  @override
  ToolOutputSchema get outputSchema => ToolOutputSchema(
        properties: {
          'uri':
              JsonSchema.string(description: 'The connected VM service URI.'),
          'sessionReportsEnabled': JsonSchema.boolean(),
          'sessionPath': JsonSchema.string(
              description: 'The new report directory, when enabled.'),
          'warning':
              JsonSchema.string(description: 'Nonfatal report setup failure.'),
        },
        required: ['uri', 'sessionReportsEnabled'],
      );

  @override
  Future<CallToolResult> execute(
      Map<String, dynamic> args, RequestHandlerExtra extra) async {
    final epoch = context.beginTransition();
    final result = await _connect(args, epoch);
    if (context.ownsConnection(epoch)) {
      context.stepLogger.logStep(name, args, result);
    }
    return result;
  }

  Future<CallToolResult> _connect(
    Map<String, dynamic> args,
    int epoch,
  ) async {
    final uri = args['uri'] as String;
    context.logger.info('Connecting to app at $uri');
    // A new connect attempt immediately supersedes whatever session
    // was active before, regardless of whether this attempt itself
    // succeeds — otherwise a call that slips in while this attempt is
    // still in flight (or after it fails) would append to a session
    // that's no longer the one actually in use.
    context.stepLogger.session = null;
    context.removeDynamicTools();

    try {
      context.ensureCurrentConnection(epoch);
      await context.connector.connect(uri);
      context.ensureCurrentConnection(epoch);

      // Version compatibility check — unwind the connection on mismatch
      // so the next call to connect can start fresh.
      try {
        final bindingVersion = await context.connector.getVersion();
        context.ensureCurrentConnection(epoch);
        if (bindingVersion != v.version) {
          await context.connector.disconnect();
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'Version mismatch: marionette_mcp is ${v.version}, '
                    'but marionette_flutter binding is $bindingVersion. '
                    'Please ensure both packages are the same version.',
              ),
            ],
          );
        }
      } catch (err) {
        context.logger.warning('Failed to check binding version', err);
        if (context.ownsConnection(epoch)) {
          await context.connector.disconnect();
        }
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: 'Failed to verify marionette_flutter binding version. '
                  'Please ensure marionette_flutter is up to date. '
                  'Error: $err',
            ),
          ],
        );
      }

      // Promote each schema-bearing custom extension into a first-class
      // MCP tool. Failures here are logged but don't fail the connect —
      // the generic call_custom_extension fallback keeps working.
      await context.registerDynamicTools();
      context.ensureCurrentConnection(epoch);

      // Session reports are opt-in app-side
      // (MarionetteConfiguration.enableSessionReports): with them off,
      // connect writes nothing to disk and steps go unlogged. Failing
      // to even determine that counts as off too, same as a session
      // directory that fails to open below — the app connection and
      // every other tool already work fine either way, so neither is
      // worth dropping an otherwise-working connection over.
      var sessionReportsEnabled = false;
      try {
        sessionReportsEnabled =
            await context.connector.getSessionReportsEnabled();
      } catch (err) {
        context.logger.warning(
          'Failed to read binding configuration; continuing without '
          'session reports',
          err,
        );
      }
      context.ensureCurrentConnection(epoch);
      if (!sessionReportsEnabled) {
        context.stepLogger.session = null;
        return CallToolResult(
          structuredContent: {'uri': uri, 'sessionReportsEnabled': false},
          content: [
            TextContent(text: 'Successfully connected to app at $uri'),
          ],
        );
      }

      try {
        final session = context.sessionManager.create(
          title: args['session_title'] as String?,
          baseDirOverride: args['session_dir'] as String?,
        );
        context.stepLogger.session = session;

        return CallToolResult(
          structuredContent: {
            'uri': uri,
            'sessionReportsEnabled': true,
            'sessionPath': session.directory.path,
          },
          content: [
            TextContent(
              text: 'Successfully connected to app at $uri\n'
                  'Opened session: ${session.directory.path}',
            ),
          ],
        );
      } catch (err) {
        // Session setup is best-effort: the app connection and every
        // other tool already work fine without it, so a directory
        // creation failure (e.g. an unwritable session_dir) shouldn't
        // drop an otherwise-working connection. Degrade the same way
        // an app that opted out of session reports already does —
        // connect succeeds, just without step logging.
        context.logger.warning(
          'Failed to open session directory; continuing without '
          'session reports',
          err,
        );
        context.stepLogger.session = null;
        return CallToolResult(
          structuredContent: {
            'uri': uri,
            'sessionReportsEnabled': false,
            'warning': err.toString(),
          },
          content: [
            TextContent(
              text: 'Successfully connected to app at $uri\n'
                  'Could not open a session directory, so this run '
                  'will not be logged: $err',
            ),
          ],
        );
      }
    } catch (err) {
      context.logger.severe('Failed to connect to app', err);
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Failed to connect to app: $err')],
      );
    }
  }
}

/// Disconnects an app while retaining its report until the final step is logged.
class DisconnectTool extends ConnectionTool {
  DisconnectTool(super.context);

  @override
  String get name => 'disconnect';

  @override
  String get description =>
      'Disconnects from the currently connected Flutter app. After disconnecting, you must call connect again to use any other tools.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Disconnect from App');

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(properties: {});

  @override
  ToolOutputSchema get outputSchema => ToolOutputSchema(
        properties: {
          'disconnected': JsonSchema.boolean(),
          'sessionPath': JsonSchema.string(
              description: 'The report directory of the closed session.'),
        },
        required: ['disconnected'],
      );

  @override
  Future<CallToolResult> execute(
      Map<String, dynamic> args, RequestHandlerExtra extra) async {
    final epoch = context.beginTransition();
    final disconnectLogger = StepLogger()..session = context.stepLogger.session;
    context.logger.info('Disconnecting from app');

    try {
      // Retire dynamic tools before tearing down the connection so a
      // mid-disconnect tools/list reflects only what's still callable.
      context.removeDynamicTools();
      await context.connector.disconnect();

      final session = disconnectLogger.session;
      final nudge = session == null
          ? ''
          : '\nSession: ${session.directory.path}\nWrite report.md now.';
      final result = CallToolResult(
        structuredContent: {
          'disconnected': true,
          if (session != null) 'sessionPath': session.directory.path,
        },
        content: [
          TextContent(
            text: 'Successfully disconnected from app$nudge',
          ),
        ],
      );
      // Attribute the step to the connection being closed. A newer
      // connect may already own a different session while cleanup waits.
      if (!context.isDisposed) {
        disconnectLogger.logStep('disconnect', args, result);
      }
      if (context.ownsConnection(epoch)) context.stepLogger.session = null;
      return result;
    } catch (err) {
      context.logger.severe('Error during disconnect', err);
      final result = CallToolResult(
        isError: true,
        content: [TextContent(text: 'Error during disconnect: $err')],
      );
      if (!context.isDisposed) {
        disconnectLogger.logStep('disconnect', args, result);
      }
      return result;
    }
  }
}
