import 'package:mcp_dart/mcp_dart.dart';

import '../session/report_steps.dart';
import '../session/session.dart';

// Record built-in confirmations, but summarize listing/extension payloads to
// avoid persisting application data. Error details remain diagnostic output.
const _shortConfirmationTools = {
  'connect',
  'disconnect',
  'tap',
  'secondary_tap',
  'double_tap',
  'long_press',
  'swipe',
  'pinch_zoom',
  'scroll_to',
  'press_back_button',
  'enter_text',
  'press_key',
  'set_device_config',
  'hot_reload',
  'hot_restart',
  'take_screenshots',
};

// Session paths and report prompts are redundant inside the report itself.
const _firstLineOnlyTools = {'connect', 'disconnect'};

/// Records one bounded outcome per call without persisting application payloads.
class StepLogger {
  /// Current report session supplied by runtime lifecycle callbacks.
  /// In-flight calls and disconnect retain their own session snapshots.
  Session? session;

  void logStep(
    String toolName,
    Map<String, dynamic> args,
    CallToolResult result,
  ) =>
      _logStep(session, toolName, args, result);

  void _logStep(
    Session? activeSession,
    String toolName,
    Map<String, dynamic> args,
    CallToolResult result,
  ) {
    if (activeSession == null) return;

    appendReportStep(
      activeSession,
      toolName,
      args,
      _describeOutcome(toolName, result, activeSession),
    );
  }

  String _describeOutcome(
    String toolName,
    CallToolResult result,
    Session session,
  ) {
    if (result.isError) {
      return describeStepError(_firstNonEmptyText(result));
    }

    if (_shortConfirmationTools.contains(toolName)) {
      var text = _firstNonEmptyText(result);
      if (_firstLineOnlyTools.contains(toolName)) {
        text = text.split('\n').first;
      }
      final confirmation = describeStepConfirmation(text, session);
      if (confirmation != null) return confirmation;
    }

    final imageCount = result.content.whereType<ImageContent>().length;
    return imageCount > 0 ? '$imageCount screenshot(s) captured' : 'ok';
  }

  String _firstNonEmptyText(CallToolResult result) => result.content
      .whereType<TextContent>()
      .map((c) => c.text)
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');
}

/// Records results and thrown failures against the invocation's original session.
/// Capturing before the await prevents reconnects from reattributing results.
ToolFunction withStepLogging(
  StepLogger stepLogger,
  String name,
  ToolFunction callback,
) {
  return (args, extra) async {
    final session = stepLogger.session;
    try {
      final result = await callback(args, extra);
      stepLogger._logStep(session, name, args, result);
      return result;
    } catch (err) {
      stepLogger._logStep(
        session,
        name,
        args,
        CallToolResult(
          isError: true,
          content: [TextContent(text: 'error: $err')],
        ),
      );
      rethrow;
    }
  };
}
