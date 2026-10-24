import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/session/session.dart';
import 'package:stack_trace/stack_trace.dart';

/// Field names that hint at a sensitive value (a password, PIN, token,
/// etc.) — matched against `enter_text`'s selector (key/identifier) to
/// decide how hard to redact the entered value in steps.md.
final _sensitiveSelectorPattern = RegExp(
  r'pass|pin|token|secret|cvv',
  caseSensitive: false,
);

const _maxOutcomeLength = 200;

/// A longer budget for an error outcome that carries a summarized stack
/// trace (see [describeStepError]) — a bare message fits the normal budget
/// comfortably, but a message plus a few compact frames often doesn't.
const _maxErrorOutcomeLength = 500;

/// Stack frames kept when an error carries a structured exception/stack
/// (see [describeStepError]) — enough to usually show where the failure
/// actually happened, without pasting the whole trace.
const _maxStackFrames = 4;

/// Arg names shown in a step's selector summary. Deliberately excludes
/// free-text payload fields (e.g. `enter_text`'s `input`) — steps.md
/// records what was acted on, not the payload.
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

/// Sanitizes a short confirmation message for a session's step log.
///
/// Callers must only use this for synthesized status messages, never arbitrary
/// application data. Paths inside the session become relative, embedded URIs
/// lose credentials, and the result fits on one bounded physical line. Returns
/// null when removing the session path leaves no confirmation text.
String? describeStepConfirmation(String text, Session session) {
  final relativeText = _relativizeSessionPaths(text, session);
  return relativeText.isEmpty
      ? null
      : _truncateText(_oneLine(_redactUrisIn(relativeText)));
}

/// Builds an error outcome (prefixed `error: `) from raw error text — either
/// an MCP tool result's own message or a CLI command's caught exception's
/// `toString()`. Both transports can surface the same
/// `VmServiceExtensionException`-shaped text
/// (`"Extension X failed\nError: {"exception": "...", "stack": "...", "method": "..."}"`
/// — see `VmServiceExtensionException.toString()` and
/// `registerInternalMarionetteExtension`'s catch-all in
/// `marionette_flutter`), so both get the same treatment: the exception
/// message plus a few compact stack frames when that shape is present,
/// instead of blindly truncating raw JSON apart mid-structure and losing the
/// message entirely on a long selector. A deliberate, expected error (e.g.
/// "no log collector configured") isn't JSON-wrapped and falls back to the
/// plain, redacted, truncated message.
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

/// Looks for the `Error: {...}` suffix `VmServiceExtensionException` appends
/// (see [describeStepError]) and parses it as JSON. Returns null for any
/// text that isn't in exactly this shape — a deliberate error message, a
/// locally-thrown exception's plain `toString()`, or anything else — rather
/// than guessing.
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

/// The first [_maxStackFrames] frames of [stackTrace] after [Trace.terse]
/// folds together consecutive Dart-core/SDK frames — so `dart:async`/
/// `dart:developer-patch` zone plumbing collapses to at most one frame (and
/// is dropped entirely if it's trailing, i.e. outermost) instead of eating
/// the whole budget on frames that don't point at application code. Falls
/// back to the raw text, one-lined, if it doesn't parse as a Dart stack
/// trace at all (defensive — the text always comes from a real
/// `StackTrace.toString()` on the app side, but a parse failure here
/// shouldn't break error logging).
String _summarizeStackTrace(String stackTrace) {
  final Trace trace;
  try {
    trace = Trace.parse(stackTrace).terse;
  } on FormatException {
    return _truncateText(_oneLine(stackTrace), _maxErrorOutcomeLength);
  }
  return trace.frames.take(_maxStackFrames).map(_formatFrame).join(' › ');
}

/// `member (path:line)` — `path` package-relative (falling back to
/// [Frame.library]'s pretty-printed form for anything else, e.g. a lone,
/// unfolded `dart:` frame), column dropped. More compact than
/// [Frame.location] (which keeps the full `package:` scheme and the
/// column), which matters against [_maxErrorOutcomeLength].
String _formatFrame(Frame frame) {
  final path = frame.uri.scheme == 'package' ? frame.uri.path : frame.library;
  return frame.line == null
      ? '${frame.member} ($path)'
      : '${frame.member} ($path:${frame.line})';
}

/// Rewrites absolute paths inside [session]'s directory as paths relative
/// to it — e.g. `take_screenshots`' saved paths become `screenshots/01.png`,
/// which is also how a report living next to steps.md cites them.
String _relativizeSessionPaths(String text, Session session) =>
    text.replaceAll('${session.directory.path}${Platform.pathSeparator}', '');

String _truncateText(String text, [int maxLength = _maxOutcomeLength]) =>
    text.length <= maxLength ? text : '${text.substring(0, maxLength)}…';

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
/// MCP tool calls and CLI command invocations, which
/// use the same field names.
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
