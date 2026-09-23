import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/session/session_manager.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:marionette_mcp/src/version.g.dart' as v;
import 'package:marionette_mcp/src/vm_service/dynamic_extension_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/device_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/extension_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/gesture_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/keyboard_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/system_tools.dart';
import 'package:marionette_mcp/src/vm_service/tools/text_tools.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Context for managing VM service connection and registering MCP tools.
final class VmServiceContext {
  VmServiceContext()
      : connector = VmServiceConnector(),
        _logger = logging.Logger('VmServiceContext'),
        _sessionManager = SessionManager(),
        _stepLogger = StepLogger();

  final VmServiceConnector connector;
  final logging.Logger _logger;
  final SessionManager _sessionManager;
  final StepLogger _stepLogger;

  /// Owns the registry of dynamic extension tools across the lifetime of
  /// this context. Reused across connect/disconnect cycles so a previously
  /// disabled tool can be revived in place — see [DynamicExtensionTools].
  late final DynamicExtensionTools _dynamicTools;

  /// Registers all VM service related tools with the MCP server.
  ///
  /// Every tool is registered through [LoggedMcpServer] so each call is
  /// recorded to the active session's steps.md (see [StepLogger]) — except
  /// `connect`/`disconnect`, registered on the raw server: they own the
  /// version-compatibility handshake with the binding and the session
  /// lifecycle itself (creating it, and — for `disconnect` — clearing it
  /// right after logging its own step, which the generic wrapper has no
  /// hook for), so they log manually instead of going through
  /// [LoggedMcpServer]. Everything else is delegated to themed registration
  /// functions.
  void registerTools(McpServer server) {
    final loggedServer = LoggedMcpServer(server, _stepLogger);
    _dynamicTools = DynamicExtensionTools(
      server: server,
      connector: connector,
      logger: _logger,
      stepLogger: _stepLogger,
    );
    _registerConnectionTools(server);
    registerInspectionTools(loggedServer, connector, _logger);
    registerGestureTools(loggedServer, connector, _logger);
    registerTextTools(loggedServer, connector, _logger);
    registerKeyboardTools(loggedServer, connector, _logger);
    registerDeviceTools(loggedServer, connector, _logger);
    registerExtensionTools(loggedServer, connector, _logger);
    registerSystemTools(loggedServer, connector, _logger);
  }

  void _registerConnectionTools(McpServer server) {
    server
      ..registerTool(
        'connect',
        description:
            'Connects to a Flutter app via its VM service URI. This must be called before using any other tools. The VM service URI is typically in the format ws://127.0.0.1:PORT/ws and can be found in the Flutter app output when running in debug mode. On success this also opens (or resumes) a session directory under .marionette/sessions/ where the step log and screenshots for this run are kept — pass session_title again on a later connect to resume the same one.',
        annotations: const ToolAnnotations(title: 'Connect to App'),
        inputSchema: ToolInputSchema(
          properties: {
            'uri': JsonSchema.string(
              description:
                  'VM service URI (e.g., ws://127.0.0.1:8181/ws). This is printed in the Flutter app console when running in debug mode.',
            ),
            'session_title': JsonSchema.string(
              description:
                  'A short title for this run, e.g. "profile validation". '
                  'Slugified and timestamped into the session directory name. '
                  'Pass the exact directory name a previous connect returned '
                  'to resume that session (e.g. after a compaction or an '
                  'interruption) instead of starting a new one — but only if '
                  'that session is still open: once it has disconnected or '
                  'has a report.md, it\'s considered concluded and a fresh '
                  'session is opened instead, even with a matching title, so '
                  'a later, unrelated run can never overwrite an already-'
                  'finished one. Falls back to "run-<timestamp>" when omitted.',
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
        ),
        callback: withStepLogging(_stepLogger, 'connect', (args, extra) async {
          final uri = args['uri'] as String;
          _logger.info('Connecting to app at $uri');

          try {
            await connector.connect(uri);

            // Version compatibility check — unwind the connection on mismatch
            // so the next call to connect can start fresh.
            try {
              final bindingVersion = await connector.getVersion();
              if (bindingVersion != v.version) {
                await connector.disconnect();
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
              _logger.warning('Failed to check binding version', err);
              await connector.disconnect();
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text:
                        'Failed to verify marionette_flutter binding version. '
                        'Please ensure marionette_flutter is up to date. '
                        'Error: $err',
                  ),
                ],
              );
            }

            // Promote each schema-bearing custom extension into a first-class
            // MCP tool. Failures here are logged but don't fail the connect —
            // the generic call_custom_extension fallback keeps working.
            await _registerDynamicTools();

            try {
              final session = _sessionManager.createOrResume(
                title: args['session_title'] as String?,
                baseDirOverride: args['session_dir'] as String?,
              );
              _stepLogger.session = session;

              return CallToolResult(
                content: [
                  TextContent(
                    text: 'Successfully connected to app at $uri\n'
                        '${session.resumed ? 'Resumed' : 'Opened'} session: '
                        '${session.directory.path}',
                  ),
                ],
              );
            } catch (err) {
              // Session setup failed after the connection (and dynamic
              // tools) were already live — roll both back rather than
              // report a failed connect while leaving the server connected.
              _logger.severe('Failed to open session directory', err);
              _disableDynamicTools();
              await connector.disconnect();
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text: 'Connected to app, but failed to open a session '
                        'directory: $err',
                  ),
                ],
              );
            }
          } catch (err) {
            _logger.severe('Failed to connect to app', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to connect to app: $err')],
            );
          }
        }),
      )
      ..registerTool(
        'disconnect',
        description:
            'Disconnects from the currently connected Flutter app. After disconnecting, you must call connect again to use any other tools.',
        annotations: const ToolAnnotations(title: 'Disconnect from App'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Disconnecting from app');

          try {
            // Retire dynamic tools before tearing down the connection so a
            // mid-disconnect tools/list reflects only what's still callable.
            _disableDynamicTools();
            await connector.disconnect();

            final session = _stepLogger.session;
            final nudge = session == null
                ? ''
                : '\nSession: ${session.directory.path}\nWrite report.md now.';
            final result = CallToolResult(
              content: [
                TextContent(
                  text: 'Successfully disconnected from app$nudge',
                ),
              ],
            );
            // Registered on the raw server (not LoggedMcpServer), so this
            // step is logged manually here — and only now, right after, is
            // the session cleared. That order matters: clearing it first
            // would mean disconnect's own line never lands anywhere, and a
            // stray call made after disconnecting — or a later failed
            // reconnect — would otherwise silently append to a session
            // whose report may already be written.
            _stepLogger.logStep('disconnect', args, result);
            _stepLogger.session = null;
            return result;
          } catch (err) {
            _logger.severe('Error during disconnect', err);
            final result = CallToolResult(
              isError: true,
              content: [TextContent(text: 'Error during disconnect: $err')],
            );
            _stepLogger.logStep('disconnect', args, result);
            return result;
          }
        },
      );
  }

  Future<void> _registerDynamicTools() async {
    // A reconnect without a clean disconnect would leak the previous
    // batch — disable any leftovers before registering fresh ones.
    _dynamicTools.disableAll();
    await _dynamicTools.registerAll();
  }

  void _disableDynamicTools() => _dynamicTools.disableAll();
}
