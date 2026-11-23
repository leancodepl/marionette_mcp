import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:marionette_mcp/src/tool_runner.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_library.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Registers read-only MCP tools that inspect the running app:
/// `get_interactive_elements`, `get_logs`, `take_screenshots`.
///
/// [nativeElements] names the tool that reads a covered screen; null when the
/// native lane is off. [requiredUiLibraries] gives the scope `connect` took
/// from a source preflight; the listing warns when the app lacks one of its
/// integrations.
void registerInspectionTools(
  LoggedMcpServer server,
  VmServiceConnector connector,
  logging.Logger logger, {
  required String? nativeElements,
  required Set<UiSupportLibrary>? Function() requiredUiLibraries,
}) {
  server
    ..registerTool(
      'get_interactive_elements',
      description:
          'Returns a list of all interactive elements currently visible in the Flutter app UI tree, one line per element. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Inside a value a line break prints as \\n, a carriage return as \\r and a backslash as \\\\: unescape them before you pass a copied value back as a selector. A control such as a button or list tile reports the labels of its children as its text. When that text joins several labels (usually printed with \\n between them), comes from a Semantics label, or includes the content of a WidgetSpan ("Hi Bob" from Text.rich with WidgetSpan(child: Text("Bob"))), it is for discovery only and the text matcher does not match it: select the element by key, identifier, the text of one visible Text widget, or coordinates. Style, decoration and colour blobs are never reported. Set compaction to "compact" (the default for most apps) to also drop icon-font glyphs and rendering details no interaction tool reads (textAlign, softWrap, overflow, font metrics, …), report visible only when an element is not visible, round bounds to whole logical pixels, and drop a Text element\'s duplicated data field — much more token-efficient for agent loops. Set compaction to "none" to force the full payload. Omit compaction to use the app\'s MarionetteConfiguration.compaction default. On Android and iOS, when the app is not in front (a system dialog, the notification shade, a biometric prompt, a browser or a native screen covers it) the result starts with a warning: the listed widgets may not be reachable${nativeElements == null ? '' : ' — use $nativeElements'}. Requires an active connection established via connect.',
      annotations: const ToolAnnotations(
        title: 'Get Interactive Elements',
        readOnlyHint: true,
        idempotentHint: true,
      ),
      inputSchema: ToolInputSchema(
        properties: {
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: _ancestorKeysDescription,
          ),
          'compaction': JsonSchema.string(
            description:
                'How much to reduce the payload. "compact" drops icon-font glyphs, rendering details, font metrics, a Text element\'s duplicated data, rounds bounds to whole logical pixels, and reports visible only when false. "none" forces the full payload. Omit to use the app\'s MarionetteConfiguration.compaction default.',
            enumValues: supportedCompactionModes.toList(),
          ),
        },
      ),
      callback: (args, extra) async {
        final compaction = args['compaction'] as String?;
        if (invalidCompactionError(compaction) case final error?) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: error)],
          );
        }

        logger.info('Getting interactive elements (compaction: $compaction)');
        return runTool(logger, 'get interactive elements', () async {
          final response = await connector.getInteractiveElements(
            ancestorKeys:
                (args['ancestor_keys'] as List<dynamic>?)?.cast<String>() ??
                    const [],
            compaction: compaction,
          );
          final elements = response['elements'] as List<dynamic>;

          final buffer = StringBuffer();
          if (coveredAppWarning(response, nativeElements: nativeElements)
              case final warning?) {
            buffer.writeln('$warning\n');
          }
          if (await _uiSupportWarning(
            connector,
            logger,
            requiredUiLibraries(),
          )
              case final warning?) {
            buffer.writeln('$warning\n');
          }
          buffer.writeln('Found ${elements.length} interactive element(s):\n');

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
          'Takes screenshots of all views in the Flutter app. By default returns base64-encoded PNG images inline, which can be decoded and saved. Set inline: false to instead save the screenshots straight into the active session directory (only available when the app enables session reports) and get back their paths — evidence you plan to cite in a report but don\'t need to look at right now, since each inline screenshot costs real visual tokens. Requires an active connection established via connect.',
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

/// How `connect` takes the UI libraries a source preflight confirmed, for
/// the UI integration status.
const uiSupportScopeHint =
    'call connect again with them in required_ui_libraries';

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
              'only created once connect succeeds and only when the app '
              'enables session reports '
              '(MarionetteConfiguration.enableSessionReports).',
        ),
      ],
    );
  }

  final paths = session.saveScreenshots(screenshots);
  return CallToolResult(
    content: [
      TextContent(
        text: 'Saved ${paths.length} screenshot(s):\n${paths.join('\n')}',
      ),
    ],
  );
}

/// The listing's warning about the app's UI integrations against
/// [requiredUiLibraries]. Null without a confirmed scope, which `connect`
/// already reported on, and when the scope is covered.
Future<String?> _uiSupportWarning(
  VmServiceConnector connector,
  logging.Logger logger,
  Set<UiSupportLibrary>? requiredUiLibraries,
) async {
  if (requiredUiLibraries == null) return null;
  try {
    final report = await connector.inspectUiSupport(
      requiredLibraries: requiredUiLibraries,
    );
    return uiSupportWarning(report, scopeHint: uiSupportScopeHint);
  } catch (err) {
    logger.warning('Failed to check UI integrations', err);
    return 'Warning: could not check UI integrations: $err';
  }
}

/// `ancestor_keys` as worded for `get_interactive_elements`, which lists a
/// subtree rather than matching one element inside it.
///
/// Kept separate from the matcher tools' `ancestorKeysDescription` because
/// the field means something else here: the scope alone is the whole request,
/// and it lists that subtree instead of limiting where one element is
/// searched for.
const _ancestorKeysDescription =
    'Optional wrapper keys (ValueKey<String>), outermost first; each is '
    'looked up inside the previous one. Lists only that subtree. Fails if a '
    'key has no element.';
