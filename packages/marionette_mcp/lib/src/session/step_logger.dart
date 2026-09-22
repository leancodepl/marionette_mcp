import 'dart:io';

import 'package:marionette_mcp/src/session/session.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Field names that hint at a sensitive value (a password, PIN, token,
/// etc.) — matched against `enter_text`'s selector (key/identifier) to
/// decide how hard to redact the entered value in steps.md.
final _sensitiveSelectorPattern = RegExp(
  r'pass|pin|token|secret|cvv',
  caseSensitive: false,
);

const _maxOutcomeLength = 200;

/// Arg names shown in a step's selector summary. Deliberately excludes
/// free-text payload fields (e.g. `enter_text`'s `input`) — steps.md
/// records what was acted on, not the payload.
const _selectorArgKeys = ['key', 'identifier', 'text', 'type', 'uri', 'x', 'y'];

/// Appends one line per tool call to the active session's steps.md: tool,
/// selector, outcome. No payloads. No-ops when there is no active session
/// (nothing connected yet).
class StepLogger {
  /// The session tool calls are currently logged into. Set by `connect` on
  /// success; left in place by `disconnect` so its own step still lands in
  /// the session it belongs to.
  Session? session;

  void logStep(
    String toolName,
    Map<String, dynamic> args,
    CallToolResult result,
  ) {
    final activeSession = session;
    if (activeSession == null) return;

    final selector = describeStepSelector(toolName, args);
    final outcome = _describeOutcome(result);
    final line = formatStepLine(toolName, selector, outcome);

    activeSession.stepsFile.writeAsStringSync('$line\n', mode: FileMode.append);
  }

  String _describeOutcome(CallToolResult result) {
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .firstWhere((t) => t.isNotEmpty, orElse: () => '');
    final imageCount = result.content.whereType<ImageContent>().length;

    final body = text.isNotEmpty
        ? _truncate(_oneLine(text))
        : (imageCount > 0 ? '$imageCount screenshot(s) captured' : 'ok');
    return result.isError ? 'error: $body' : body;
  }

  String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _truncate(String text) => text.length <= _maxOutcomeLength
      ? text
      : '${text.substring(0, _maxOutcomeLength)}…';
}

/// Builds the selector portion of a step line from [args] — the small set
/// of curated fields (key, identifier, text, etc.) that describe what a call
/// acted on, deliberately excluding free-text payload fields. Shared between
/// [StepLogger] (MCP tool calls) and the CLI (command invocations), which
/// use the same field names.
String describeStepSelector(String toolName, Map<String, dynamic> args) {
  final parts = <String>[
    for (final key in _selectorArgKeys)
      if (args[key] != null) '$key=${args[key]}',
  ];
  if (args['focused_element'] == true) parts.add('focused_element=true');
  if (args['coordinates'] case final Map<String, dynamic> coordinates) {
    parts.add('x=${coordinates['x']} y=${coordinates['y']}');
  }
  // Matches both the MCP tool name (enter_text) and the CLI command name
  // (enter-text).
  if (toolName.replaceAll('-', '_') == 'enter_text') {
    parts.add(_describeEnterTextInput(args));
  }
  return parts.join(' ');
}

/// `enter_text`'s value is never written in full: only its length, or — when
/// the selector looks like a sensitive field (password, PIN, token, secret,
/// CVV) — not even that.
String _describeEnterTextInput(Map<String, dynamic> args) {
  final selectorValue = (args['key'] ?? args['identifier'] ?? '').toString();
  if (_sensitiveSelectorPattern.hasMatch(selectorValue)) {
    return 'input=[redacted]';
  }
  final input = args['input'] as String? ?? '';
  return 'input_len=${input.length}';
}

/// Formats one steps.md line: a timestamp, the tool/command name, its
/// selector (if any), and the outcome.
String formatStepLine(String toolName, String selector, String outcome) {
  final time = _formatTime(DateTime.now());
  return selector.isEmpty
      ? '- [$time] $toolName -> $outcome'
      : '- [$time] $toolName $selector -> $outcome';
}

String _formatTime(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// Wraps [callback] so every call is recorded as one line in the active
/// session's steps.md via [stepLogger] before the result is returned to the
/// client.
ToolFunction withStepLogging(
  StepLogger stepLogger,
  String name,
  ToolFunction callback,
) {
  return (args, extra) async {
    final result = await callback(args, extra);
    stepLogger.logStep(name, args, result);
    return result;
  };
}

/// A drop-in [McpServer] substitute whose `registerTool` logs every call to
/// the active session's steps.md (see [withStepLogging]) before delegating
/// to the real server.
///
/// Passed to every `register*Tools` function in place of the raw server so
/// step logging happens uniformly, without each tool file having to call
/// back into a logger itself.
class LoggedMcpServer {
  LoggedMcpServer(this._server, this.stepLogger);

  final McpServer _server;

  /// Exposed so a tool that needs the active session directly (currently
  /// only `take_screenshots`, to save files into it) can reach it.
  final StepLogger stepLogger;

  RegisteredTool registerTool(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    required ToolFunction callback,
  }) {
    return _server.registerTool(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: annotations,
      meta: meta,
      callback: withStepLogging(stepLogger, name, callback),
    );
  }
}
