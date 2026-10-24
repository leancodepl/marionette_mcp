import 'package:mcp_dart/mcp_dart.dart';

import '../session/report_steps.dart';
import '../session/session.dart';

/// Tools whose successful result is a short, synthesized confirmation
/// message (e.g. "Successfully tapped"), never a dump of application data —
/// safe to echo verbatim (truncated) in steps.md. Everything else —
/// data-listing tools (`get_interactive_elements`, `get_logs`,
/// `call_custom_extension`, `list_custom_extensions`) and any
/// dynamically-promoted custom extension tool, whose result may carry
/// arbitrary app data — gets a generic outcome on success instead, so
/// steps.md never ends up persisting a payload. Error messages are shown
/// regardless of the tool (see [_describeOutcome]): they're diagnostic
/// context the report contract explicitly wants, not a payload.
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

/// Tools whose success message is one status line followed by session
/// bookkeeping aimed at the agent — `connect`'s "Opened session: <path>",
/// `disconnect`'s "Session: <path>" and its report nudge. That tail is
/// redundant inside the very session it points at (and, being an absolute
/// path, mostly lost to truncation), so only the first line is logged.
const _firstLineOnlyTools = {'connect', 'disconnect'};

/// Appends one line per tool call to the active session's steps.md: tool,
/// selector, outcome. No payloads. No-ops when there is no active session
/// (nothing connected yet).
class StepLogger {
  /// The session tool calls are currently logged into. Set by `connect` on
  /// success; cleared both at the very start of every `connect` attempt and
  /// once `disconnect`'s own step has been logged (see `VmServiceContext`),
  /// so neither a stray call made while disconnected nor one that slips in
  /// during a reconnect attempt — successful or not — can silently append
  /// to a session whose report may already be written.
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

/// Wraps [callback] so every call is recorded as one line in the active
/// session's steps.md via [stepLogger] before the result is returned to the
/// client — including a call [callback] itself throws out of (an
/// unexpected, un-caught error rather than the usual `isError: true`
/// result), so the report contract's `Tested:` line — rendered from
/// steps.md, not the agent's own claim — never silently undercounts an
/// attempt just because it failed in an unanticipated way. The session is
/// captured when the call starts, so reconnects cannot reattribute its result.
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
