import 'package:marionette_mcp/src/mcp/step_logging.dart';
import 'package:marionette_mcp/src/vm_service/app_connection_service.dart';
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
    final outcome = await context.connection.connect(
      uri: args['uri'] as String,
      sessionTitle: args['session_title'] as String?,
      sessionDir: args['session_dir'] as String?,
    );
    final result = _result(outcome);
    if (context.connection.ownsConnection(outcome.generation)) {
      context.stepLogger.logStep(name, args, result);
    }
    return result;
  }

  CallToolResult _result(AppConnectionResult outcome) {
    final failure = outcome.failure;
    if (failure != null) {
      final text = switch (failure.kind) {
        AppConnectionFailureKind.versionMismatch =>
          'Version mismatch: marionette_mcp is ${context.connection.expectedVersion}, '
              'but marionette_flutter binding is ${failure.actualVersion}. '
              'Please ensure both packages are the same version.',
        AppConnectionFailureKind.versionCheck =>
          'Failed to verify marionette_flutter binding version. '
              'Please ensure marionette_flutter is up to date. '
              'Error: ${failure.cause}',
        AppConnectionFailureKind.connection =>
          'Failed to connect to app: ${failure.cause}',
      };
      return CallToolResult(isError: true, content: [TextContent(text: text)]);
    }
    final session = outcome.session;
    final warning = outcome.reportWarning;
    final text = 'Successfully connected to app at ${outcome.uri}';
    return CallToolResult(
      structuredContent: {
        'uri': outcome.uri,
        'sessionReportsEnabled': session != null,
        if (session != null) 'sessionPath': session.directory.path,
        if (warning != null) 'warning': warning.toString(),
      },
      content: [
        TextContent(
          text: session != null
              ? '$text\nOpened session: ${session.directory.path}'
              : warning != null
                  ? '$text\nCould not open a session directory, so this run '
                      'will not be logged: $warning'
                  : text,
        ),
      ],
    );
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
    final outcome = await context.connection.disconnect();
    final disconnectLogger = StepLogger()..session = outcome.closingSession;
    final session = outcome.closingSession;
    final error = outcome.error;
    final nudge = session == null
        ? ''
        : '\nSession: ${session.directory.path}\nWrite report.md now.';
    final result = error == null
        ? CallToolResult(
            structuredContent: {
              'disconnected': true,
              if (session != null) 'sessionPath': session.directory.path,
            },
            content: [
              TextContent(text: 'Successfully disconnected from app$nudge'),
            ],
          )
        : CallToolResult(
            isError: true,
            content: [TextContent(text: 'Error during disconnect: $error')],
          );
    if (!context.isDisposed) {
      disconnectLogger.logStep('disconnect', args, result);
    }
    return result;
  }
}
