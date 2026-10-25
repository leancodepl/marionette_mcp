import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/session/session.dart';
import 'package:stack_trace/stack_trace.dart';

// Sensitive selectors suppress even the entered value's length.
final _sensitiveSelectorPattern = RegExp(
  r'pass|pin|token|secret|cvv',
  caseSensitive: false,
);

const _maxOutcomeLength = 200;

// Allow room for a bounded error message and stack summary.
const _maxErrorOutcomeLength = 500;

// Keep a few useful frames without persisting the full trace.
const _maxStackFrames = 4;

// Selector summaries exclude free-text input payloads.
const _selectorArgKeys = ['key', 'identifier', 'text', 'type', 'uri', 'x', 'y'];

/// Appends one formatted step to [session], treating filesystem failures as
/// best-effort bookkeeping so they cannot turn a completed action into an error.
void appendReportStep(
  Session session,
  String toolName,
  Map<String, dynamic> args,
  String outcome,
) {
  final selector = describeStepSelector(toolName, args);
  final line = formatStepLine(toolName, selector, outcome);
  try {
    session.stepsFile.writeAsStringSync('$line\n', mode: FileMode.append);
  } on FileSystemException catch (err) {
    logging.Logger('StepLogger').warning('Failed to write steps.md', err);
  }
}

/// Sanitizes synthesized confirmations; never pass arbitrary application data.
/// Relativizes paths, redacts URI credentials, and bounds the result to one line.
/// Returns null when no confirmation text remains.
String? describeStepConfirmation(String text, Session session) {
  final relativeText = _relativizeSessionPaths(text, session);
  return relativeText.isEmpty
      ? null
      : _truncateText(_oneLine(_redactUrisIn(relativeText)));
}

/// Summarizes MCP or CLI errors without persisting URI credentials.
/// Structured extension errors include a few stack frames; other errors use
/// bounded plain text.
String describeStepError(String text) {
  if (text.isEmpty) return 'error: failed';

  final exceptionData = _tryParseExceptionJson(text);
  if (exceptionData != null) {
    final exception =
        _oneLine(_redactUrisIn(exceptionData['exception'] as String));
    final frames = _summarizeStackTrace(exceptionData['stack'] as String);
    final body = frames.isEmpty ? exception : '$exception [$frames]';
    return 'error: ${_truncateText(body, _maxErrorOutcomeLength)}';
  }

  return 'error: ${_truncateText(_oneLine(_redactUrisIn(text)))}';
}

// Recognize only the VM extension's structured error suffix; other formats
// fall back to plain text rather than guessing.
Map<String, dynamic>? _tryParseExceptionJson(String text) {
  const marker = 'Error: ';
  final index = text.indexOf('$marker{');
  if (index == -1) return null;
  try {
    final decoded = jsonDecode(text.substring(index + marker.length));
    if (decoded is! Map<String, dynamic>) return null;
    return decoded['exception'] is String && decoded['stack'] is String
        ? decoded
        : null;
  } on FormatException {
    return null;
  }
}

// Trace.terse folds SDK plumbing so the budget favors application frames.
// Malformed traces fall back to bounded text without interrupting reporting.
String _summarizeStackTrace(String stackTrace) {
  final Trace trace;
  try {
    trace = Trace.parse(stackTrace).terse;
  } on FormatException {
    return _truncateText(_oneLine(stackTrace), _maxErrorOutcomeLength);
  }
  return trace.frames.take(_maxStackFrames).map(_formatFrame).join(' › ');
}

// Omit package schemes and columns to keep frame summaries compact.
String _formatFrame(Frame frame) {
  final path = frame.uri.scheme == 'package' ? frame.uri.path : frame.library;
  return frame.line == null
      ? '${frame.member} ($path)'
      : '${frame.member} ($path:${frame.line})';
}

// Report links use paths relative to the owning session directory.
String _relativizeSessionPaths(String text, Session session) =>
    text.replaceAll('${session.directory.path}${Platform.pathSeparator}', '');

String _truncateText(String text, [int maxLength = _maxOutcomeLength]) =>
    text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';

// One physical line per step, even for multiline selectors or errors.
String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

// Redact credentials in outcomes as well as selectors: connect/error messages
// can repeat the VM service URI outside its dedicated argument.
final _uriPattern = RegExp(r'(?:wss?|https?)://\S+');

// VM service paths can contain live authentication tokens; retain only origin.
String _redactUri(String raw) {
  final parsed = Uri.tryParse(raw);
  if (parsed == null || parsed.host.isEmpty) return '[uri]';
  return '${parsed.scheme}://${parsed.host}:${parsed.port}';
}

// Apply URI redaction throughout free-form text.
String _redactUrisIn(String text) =>
    text.replaceAllMapped(_uriPattern, (m) => _redactUri(m[0]!));

/// Summarizes the target shared by MCP calls and CLI commands, excluding input.
String describeStepSelector(String toolName, Map<String, dynamic> args) {
  final parts = <String>[
    for (final key in _selectorArgKeys)
      if (args[key] != null)
        key == 'uri'
            ? 'uri=${_redactUri(args[key].toString())}'
            : '$key=${_oneLine(args[key].toString())}',
  ];
  // The MCP field is `ancestor_keys`, the CLI option `--ancestor-keys`. The
  // keys are joined with `>` rather than written as a Dart list, whose
  // `[a, b]` form would put a space inside a single part of the line.
  final ancestorKeys = args['ancestor_keys'] ?? args['ancestor-keys'];
  if (ancestorKeys is List && ancestorKeys.isNotEmpty) {
    parts.add('ancestor_keys=${_oneLine(ancestorKeys.join('>'))}');
  }
  // Only present when the caller overrode the app's default, so the log shows
  // whether a listing was the full payload or the compact one.
  if (args['compaction'] case final String compaction) {
    parts.add('compaction=${_oneLine(compaction)}');
  }
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
