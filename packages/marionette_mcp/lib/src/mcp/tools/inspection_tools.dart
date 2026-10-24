import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/mcp/tools/tool_runner.dart';
import 'package:marionette_mcp/src/session/screenshot_service.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'base_tool.dart';

/// Creates the inspection tools with their shared dependencies.
List<BaseTool> createInspectionTools({
  required VmServiceConnector connector,
  required logging.Logger logger,
  required ScreenshotService screenshotService,
  required Session? Function() currentSession,
}) =>
    [
      GetInteractiveElementsTool(connector, logger),
      GetLogsTool(connector, logger),
      TakeScreenshotsTool(screenshotService, logger, currentSession),
    ];

/// MCP tool `get_interactive_elements`.
class GetInteractiveElementsTool extends BaseTool {
  GetInteractiveElementsTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'get_interactive_elements';

  @override
  String get description =>
      'Returns a list of all interactive elements currently visible in the Flutter app UI tree. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Style, decoration and colour blobs are never reported. Set compaction to "compact" (the default for most apps) to also drop rendering details no interaction tool reads (textAlign, softWrap, overflow, font metrics, …), report visible only when an element is not visible, round bounds to whole logical pixels, and drop a Text element\'s duplicated data field — much more token-efficient for agent loops. Set compaction to "none" to force the full payload. Omit compaction to use the app\'s MarionetteConfiguration.compaction default. Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations => const ToolAnnotations(
        title: 'Get Interactive Elements',
        readOnlyHint: true,
        idempotentHint: true,
      );

  @override
  ToolOutputSchema get outputSchema => ToolOutputSchema(
        properties: {
          'elements': JsonSchema.array(
            items: JsonSchema.object(
              properties: {},
              additionalProperties: true,
            ),
          ),
          'count': JsonSchema.integer(),
        },
        required: ['elements', 'count'],
      );

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'ancestor_keys': JsonSchema.array(
            items: JsonSchema.string(),
            description: _ancestorKeysDescription,
          ),
          'compaction': JsonSchema.string(
            description:
                'How much to reduce the payload. "compact" drops rendering details, font metrics, a Text element\'s duplicated data, rounds bounds to whole logical pixels, and reports visible only when false. "none" forces the full payload. Omit to use the app\'s MarionetteConfiguration.compaction default.',
            enumValues: supportedCompactionModes.toList(),
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    final compaction = args['compaction'] as String?;
    if (invalidCompactionError(compaction) case final error?) {
      return CallToolResult(isError: true, content: [TextContent(text: error)]);
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

      final buffer = StringBuffer()
        ..writeln('Found ${elements.length} interactive element(s):\n');

      for (final element in elements) {
        buffer.writeln(formatElement(element as Map<String, dynamic>));
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString())],
        structuredContent: {'elements': elements, 'count': elements.length},
      );
    });
  }
}

/// MCP tool `get_logs`.
class GetLogsTool extends BaseTool {
  GetLogsTool(this.connector, this.logger);

  final VmServiceConnector connector;
  final logging.Logger logger;

  @override
  String get name => 'get_logs';

  @override
  String get description =>
      'Retrieves all application logs collected from the Flutter app since app start or since the last hot reload. This includes debug messages, errors, and other log output from the running app. Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Get Application Logs', readOnlyHint: true);

  @override
  ToolOutputSchema get outputSchema => ToolOutputSchema(
        properties: {
          'logs': JsonSchema.array(items: JsonSchema.string()),
          'count': JsonSchema.integer(),
        },
        required: ['logs', 'count'],
      );

  @override
  ToolInputSchema get inputSchema => const ToolInputSchema(properties: {});

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    logger.info('Getting application logs');

    try {
      final response = await connector.getLogs();
      final logs = response['logs'] as List;
      final count = response['count'] as int;

      if (count == 0) {
        return CallToolResult(
          content: [const TextContent(text: 'No logs collected')],
          structuredContent: {'logs': logs, 'count': count},
        );
      }

      final buffer = StringBuffer()
        ..writeln('Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n');

      for (final log in logs) {
        buffer.writeln(log);
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString())],
        structuredContent: {'logs': logs, 'count': count},
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
  }
}

/// MCP tool `take_screenshots`.
class TakeScreenshotsTool extends BaseTool {
  TakeScreenshotsTool(this.screenshotService, this.logger, this.currentSession);

  final ScreenshotService screenshotService;
  final logging.Logger logger;
  final Session? Function() currentSession;

  @override
  String get name => 'take_screenshots';

  @override
  String get description =>
      'Takes screenshots of all views in the Flutter app. By default returns base64-encoded PNG images inline, which can be decoded and saved. Set inline: false to instead save the screenshots straight into the active session directory (only available when the app enables session reports) and get back their paths — evidence you plan to cite in a report but don\'t need to look at right now, since each inline screenshot costs real visual tokens. Requires an active connection established via connect.';

  @override
  ToolAnnotations get annotations =>
      const ToolAnnotations(title: 'Take Screenshots', readOnlyHint: true);

  @override
  ToolOutputSchema get outputSchema => ToolOutputSchema(
        properties: {
          'count': JsonSchema.integer(),
          'inline': JsonSchema.boolean(),
          'paths': JsonSchema.array(items: JsonSchema.string()),
        },
        required: ['count', 'inline'],
      );

  @override
  ToolInputSchema get inputSchema => ToolInputSchema(
        properties: {
          'inline': JsonSchema.boolean(
            description:
                'If false, saves the screenshots into the session directory '
                'and returns their paths instead of the image data. '
                'Defaults to true.',
          ),
        },
      );

  @override
  Future<CallToolResult> execute(
    Map<String, dynamic> args,
    RequestHandlerExtra extra,
  ) async {
    logger.info('Taking screenshots');
    return runTool(
      logger,
      'take screenshots',
      () => _captureScreenshots(screenshotService, currentSession(), args),
    );
  }
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
) =>
    _captureScreenshots(ScreenshotService(connector), session, args);

Future<CallToolResult> _captureScreenshots(
  ScreenshotService screenshotService,
  Session? session,
  Map<String, dynamic> args,
) async {
  try {
    final capture = await screenshotService.capture(
      inline: args['inline'] != false,
      session: session,
    );
    return _screenshotResult(capture);
  } on ScreenshotSessionRequired {
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
}

CallToolResult _screenshotResult(ScreenshotCapture capture) {
  if (capture.count == 0) {
    return CallToolResult(
      content: [const TextContent(text: 'No screenshots captured')],
      structuredContent: {'count': 0, 'inline': capture.inline},
    );
  }

  if (capture.inline) {
    return CallToolResult(
      structuredContent: {'count': capture.count, 'inline': true},
      content: capture.images
          .map((image) => ImageContent(data: image, mimeType: 'image/png'))
          .toList(),
    );
  }

  return CallToolResult(
    structuredContent: {
      'count': capture.count,
      'inline': false,
      'paths': capture.paths,
    },
    content: [
      TextContent(
        text:
            'Saved ${capture.count} screenshot(s):\n${capture.paths.join('\n')}',
      ),
    ],
  );
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
