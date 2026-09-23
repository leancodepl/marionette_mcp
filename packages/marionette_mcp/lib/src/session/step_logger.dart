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

/// Appends one line per tool call to the active session's steps.md: tool,
/// selector, outcome. No payloads. No-ops when there is no active session
/// (nothing connected yet).
class StepLogger {
  /// The session tool calls are currently logged into. Set by `connect` on
  /// success; cleared once `disconnect`'s own step has been logged, so a
  /// stray call made while disconnected — or a later failed reconnect —
  /// can't silently append to a session whose report may already be
  /// written.
  Session? session;

  void logStep(
    String toolName,
    Map<String, dynamic> args,
    CallToolResult result,
  ) {
    final activeSession = session;
    if (activeSession == null) return;

    final selector = describeStepSelector(toolName, args);
    final outcome = _describeOutcome(toolName, result);
    final line = formatStepLine(toolName, selector, outcome);

    activeSession.stepsFile.writeAsStringSync('$line\n', mode: FileMode.append);
  }

  String _describeOutcome(String toolName, CallToolResult result) {
    if (result.isError) {
      final text = _firstNonEmptyText(result);
      return 'error: ${text.isEmpty ? 'failed' : _truncate(_oneLine(_redactUrisIn(text)))}';
    }

    if (_shortConfirmationTools.contains(toolName)) {
      final text = _firstNonEmptyText(result);
      if (text.isNotEmpty) return _truncate(_oneLine(_redactUrisIn(text)));
    }

    final imageCount = result.content.whereType<ImageContent>().length;
    return imageCount > 0 ? '$imageCount screenshot(s) captured' : 'ok';
  }

  String _firstNonEmptyText(CallToolResult result) => result.content
      .whereType<TextContent>()
      .map((c) => c.text)
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');

  String _truncate(String text) => text.length <= _maxOutcomeLength
      ? text
      : '${text.substring(0, _maxOutcomeLength)}…';
}

/// Collapses whitespace (including newlines) into single spaces and trims
/// the ends — keeps a value that might itself span multiple lines (a
/// multiline `text` selector, a multi-line tool message) from breaking
/// steps.md's one-physical-line-per-call format.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Matches a `ws(s)://`/`http(s)://` URI so one can be found and redacted
/// wherever it appears in free-form text — not just in the `uri` selector
/// field. `connect`'s own success/error text embeds the full uri a second
/// time (`"Successfully connected to app at $uri..."`, and a thrown
/// connection error's message commonly does too), so redacting only the
/// selector still left that same credential reaching steps.md through the
/// outcome.
final _uriPattern = RegExp(r'(?:wss?|https?)://\S+');

/// A VM service (or DevTools) URI stripped to `scheme://host:port`.
/// Flutter's VM service URIs commonly embed an auth token as a path segment
/// (`ws://127.0.0.1:PORT/TOKEN=/ws`) — logging one verbatim would persist a
/// live credential to steps.md.
String _redactUri(String raw) {
  final parsed = Uri.tryParse(raw);
  if (parsed == null || parsed.host.isEmpty) return '[uri]';
  return '${parsed.scheme}://${parsed.host}:${parsed.port}';
}

/// Redacts (see [_redactUri]) every URI found anywhere within [text].
String _redactUrisIn(String text) =>
    text.replaceAllMapped(_uriPattern, (m) => _redactUri(m[0]!));

/// Builds the selector portion of a step line from [args] — the small set
/// of curated fields (key, identifier, text, etc.) that describe what a call
/// acted on, deliberately excluding free-text payload fields. Shared between
/// [StepLogger] (MCP tool calls) and the CLI (command invocations), which
/// use the same field names.
String describeStepSelector(String toolName, Map<String, dynamic> args) {
  final parts = <String>[
    for (final key in _selectorArgKeys)
      if (args[key] != null)
        key == 'uri'
            ? 'uri=${_redactUri(args[key].toString())}'
            : '$key=${_oneLine(args[key].toString())}',
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
/// back into a logger itself. `connect`/`disconnect` are the exception —
/// registered on the raw server so `disconnect` can clear [StepLogger.session]
/// immediately after its own step is logged (see [vm_service_context.dart]).
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
