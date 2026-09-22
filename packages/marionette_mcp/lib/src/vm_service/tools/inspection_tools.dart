import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:marionette_mcp/src/vm_service/tools/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;

/// Registers read-only MCP tools that inspect the running app:
/// `get_interactive_elements`, `get_logs`, `take_screenshots`.
void registerInspectionTools(
  LoggedMcpServer server,
  VmServiceConnector connector,
  logging.Logger logger,
) {
  server
    ..registerTool(
      'get_interactive_elements',
      description:
          'Returns a list of all interactive elements currently visible in the Flutter app UI tree. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Get Interactive Elements',
        readOnlyHint: true,
        idempotentHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Getting interactive elements');
        return runTool(logger, 'get interactive elements', () async {
          final response = await connector.getInteractiveElements();
          final elements = response['elements'] as List<dynamic>;

          final buffer = StringBuffer()
            ..writeln('Found ${elements.length} interactive element(s):\n');

          for (final element in elements) {
            buffer.writeln(formatElement(element as Map<String, dynamic>));
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
          );
        });
      },
    )
    ..registerTool(
      'get_logs',
      description:
          'Retrieves all application logs collected from the Flutter app since app start or since the last hot reload. This includes debug messages, errors, and other log output from the running app. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Get Application Logs',
        readOnlyHint: true,
      ),
      inputSchema: const ToolInputSchema(properties: {}),
      callback: (args, extra) async {
        logger.info('Getting application logs');

        try {
          final response = await connector.getLogs();
          final logs = response['logs'] as List;
          final count = response['count'] as int;

          if (count == 0) {
            return CallToolResult(
              content: [const TextContent(text: 'No logs collected')],
            );
          }

          final buffer = StringBuffer()
            ..writeln(
              'Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n',
            );

          for (final log in logs) {
            buffer.writeln(log);
          }

          return CallToolResult(
            content: [TextContent(text: buffer.toString())],
          );
        } on VmServiceExtensionException catch (err) {
          // Surface the VM service's own error message verbatim — it carries
          // setup instructions for enabling log collection.
          logger.warning('Failed to get logs', err);
          return CallToolResult(
            isError: true,
            content: [TextContent(text: err.error ?? err.message)],
          );
        } catch (err) {
          logger.warning('Failed to get logs', err);
          return CallToolResult(
            isError: true,
            content: [TextContent(text: err.toString())],
          );
        }
      },
    )
    ..registerTool(
      'take_screenshots',
      description:
          'Takes screenshots of all views in the Flutter app. By default returns base64-encoded PNG images inline, which can be decoded and saved. Set inline: false to instead save the screenshots straight into the active session directory and get back their paths — evidence you plan to cite in a report but don\'t need to look at right now, since each inline screenshot costs real visual tokens. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Take Screenshots',
        readOnlyHint: true,
      ),
      inputSchema: ToolInputSchema(
        properties: {
          'inline': JsonSchema.boolean(
            description:
                'If false, saves the screenshots into the session directory '
                'and returns their paths instead of the image data. '
                'Defaults to true.',
          ),
        },
      ),
      callback: (args, extra) async {
        logger.info('Taking screenshots');
        return runTool(
          logger,
          'take screenshots',
          () => takeScreenshots(connector, server.stepLogger.session, args),
        );
      },
    );
}

/// Handles a `take_screenshots` invocation: captures via [connector], then
/// either returns the images inline or — when `args['inline'] == false` —
/// saves them into [session]'s screenshots directory and returns their paths.
///
/// Extracted from the tool callback so the inline/save-only branching can be
/// exercised in isolation.
Future<CallToolResult> takeScreenshots(
  VmServiceConnector connector,
  Session? session,
  Map<String, dynamic> args,
) async {
  final inline = args['inline'] != false;
  final response = await connector.takeScreenshots();
  final screenshots = (response['screenshots'] as List<dynamic>).cast<String>();

  if (screenshots.isEmpty) {
    return CallToolResult(
      content: [const TextContent(text: 'No screenshots captured')],
    );
  }

  if (inline) {
    return CallToolResult(
      content: screenshots
          .map(
            (screenshot) =>
                ImageContent(data: screenshot, mimeType: 'image/png'),
          )
          .toList(),
    );
  }

  if (session == null) {
    return CallToolResult(
      isError: true,
      content: [
        const TextContent(
          text: 'inline: false requires an active session, which is '
              'only created once connect succeeds.',
        ),
      ],
    );
  }

  final paths = _saveScreenshots(session.screenshotsDir, screenshots);
  return CallToolResult(
    content: [
      TextContent(
        text: 'Saved ${paths.length} screenshot(s):\n${paths.join('\n')}',
      ),
    ],
  );
}

/// Saves each base64-encoded PNG in [screenshots] into [screenshotsDir],
/// numbered sequentially after whatever is already there, and returns the
/// paths written to.
List<String> _saveScreenshots(
  Directory screenshotsDir,
  List<String> screenshots,
) {
  screenshotsDir.createSync(recursive: true);
  var nextIndex = screenshotsDir
          .listSync()
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.png')
          .length +
      1;

  final paths = <String>[];
  for (final screenshot in screenshots) {
    final path = p.join(
      screenshotsDir.path,
      '${nextIndex.toString().padLeft(2, '0')}.png',
    );
    File(path).writeAsBytesSync(base64Decode(screenshot));
    paths.add(path);
    nextIndex++;
  }
  return paths;
}
