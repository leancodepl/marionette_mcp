import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/step_session.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/session/session_manager.dart';
import 'package:marionette_mcp/src/session/step_logger.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Name of the native session used when `--native-device` is not given.
const defaultNativeSession = 'default';

/// Reads the `--native-device` global option.
String nativeSessionName(ArgResults? globalResults) {
  final raw = globalResults?['native-device'] as String?;
  return (raw != null && raw.isNotEmpty) ? raw : defaultNativeSession;
}

/// The `marionette` command line that runs [command] on the native session
/// [name], for hints.
String nativeCommandLine(String name, String command) => 'marionette '
    '${name == defaultNativeSession ? '' : '--native-device $name '}$command';

/// Base class for commands that run a native-lane MCP tool against the
/// session started by `native-connect`.
///
/// Each command parses its options into the tool's arguments and calls the
/// same handler as the MCP tool, so behaviour, validation and messages are
/// shared. The device-side server keeps running between commands and the
/// WebDriver session is reused.
abstract class NativeCommand extends Command<int> {
  /// [environment] holds the environment variables the command reads.
  NativeCommand(this.nativeRegistry, this.environment);

  final NativeSessionRegistry nativeRegistry;
  final Map<String, String> environment;

  /// Names of the commands of the runner, for [cliText].
  Set<String> get _commandNames => runner!.commands.keys.toSet();

  /// Runs the shared MCP handler with [args] against [context].
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  );

  /// The tool arguments from [results], this command's parsed options;
  /// throws a usage error for malformed values.
  Map<String, dynamic> toolArguments(ArgResults results);

  /// Saves an image returned by the tool. Commands without image output
  /// report that it was dropped.
  Future<void> saveImage(ImageContent image) async {
    stderr.writeln('(image output not saved)');
  }

  /// Keeps what a successful [result] adds to [session] and returns the
  /// result as the session's steps.md records it. Unchanged by default.
  CallToolResult recordInSession(CallToolResult result, Session session) =>
      result;

  @override
  Future<int> run() async {
    final args = toolArguments(argResults!);
    final sessionName = nativeSessionName(globalResults);
    final info = nativeRegistry.get(sessionName);
    if (info == null) {
      stderr.writeln(
        'No native session "$sessionName". Start one with: '
        '${nativeCommandLine(sessionName, 'native-connect --platform android|ios')}',
      );
      return 1;
    }
    final WebDriverNativeConnector connector;
    try {
      connector = await attachNativeSession(info);
    } on NativeSessionNotRunningException catch (e) {
      stderr.writeln(
        'The native server of session "$sessionName" (${info.device}) is not '
        'running at ${e.baseUrl}: the device or simulator was restarted, or '
        'the server was stopped.\n'
        'Hint: Run "marionette native-connect" again.',
      );
      return 1;
    } catch (e) {
      stderr.writeln(
        cliText(
          'Could not attach to native session "$sessionName": $e',
          _commandNames,
        ),
      );
      return 1;
    }

    final context = NativeServiceContext()
      ..connector = connector
      ..platform = info.platform;
    final session = _openReportSession();
    try {
      final CallToolResult result;
      try {
        result = await execute(context, args);
      } catch (e) {
        _logStep(session, args, describeStepError('$e'));
        rethrow;
      }
      if (session != null) {
        final recorded =
            result.isError ? result : recordInSession(result, session);
        _logStep(session, args, describeStepOutcome(name, recorded, session));
      }
      return await _print(result);
    } finally {
      _saveSessionId(info, connector.sessionId);
      connector.release();
    }
  }

  /// Saves [sessionId] in [info] when the command replaced the session and
  /// the stored entry is still the one the command started from: a
  /// `native-disconnect` or `native-connect` that ran meanwhile wins. The
  /// command's result stands when the save fails or the stored entry was
  /// edited into a malformed one: the next command replaces the session
  /// again.
  void _saveSessionId(NativeSessionInfo info, String? sessionId) {
    if (sessionId == info.sessionId) return;
    try {
      final stored = nativeRegistry.get(info.name);
      if (stored == null ||
          stored.createdAt != info.createdAt ||
          stored.sessionId != info.sessionId) {
        return;
      }
      info.sessionId = sessionId;
      nativeRegistry.save(info);
    } on Exception catch (e) {
      if (e is! FileSystemException && e is! FormatException) rethrow;
      stderr.writeln('Warning: could not save native session "${info.name}": '
          '$e');
    }
  }

  /// The CLI cannot ask the app whether it enables session reports (a
  /// native command has no Flutter connection), so a native command logs its
  /// step only when `--session`, `--session-dir` or [sessionDirEnvVar] asks
  /// for a report directory; `--session-dir` wins over the variable, as in
  /// [SessionManager]. A directory that cannot be created costs only the
  /// step log, as in the Flutter commands.
  Session? _openReportSession() {
    final title = globalResults?['session'] as String?;
    final envDir = environment[sessionDirEnvVar]?.trim();
    final baseDir = globalResults?['session-dir'] as String? ??
        (envDir == null || envDir.isEmpty ? null : envDir);
    if (title == null && baseDir == null) return null;
    return createCliStepSession(title: title, baseDirOverride: baseDir);
  }

  void _logStep(Session? session, Map<String, dynamic> args, String outcome) {
    if (session == null) return;
    appendStepLine(
      session,
      formatStepLine(name, describeStepSelector(name, args), outcome),
    );
  }

  Future<int> _print(CallToolResult result) async {
    final isError = result.isError;
    for (final content in result.content) {
      if (content is TextContent) {
        (isError ? stderr : stdout)
            .writeln(cliText(content.text, _commandNames));
      } else if (content is ImageContent) {
        await saveImage(content);
      }
    }
    return isError ? 1 : 0;
  }

  /// Adds the element selector options (`--text`, `--text-contains`, `--id`,
  /// `--type`, `--index`). [textOption] names the exact-text option
  /// (`label` for text fields).
  void addSelectorOptions({String textOption = 'text', bool withIndex = true}) {
    argParser
      ..addOption(
        textOption,
        help: textOption == 'label'
            ? 'Exact label of the field (its text or hint).'
            : 'Exact visible text or description of the element.',
      )
      ..addOption('text-contains', help: 'Substring of the visible text.')
      ..addOption(
        'id',
        help: 'Resource id (Android) or accessibility identifier (iOS). On '
            'Android it matches the full resource id (package:id/name) only.',
      )
      ..addOption(
        'type',
        help: 'Element type as listed by native-get-elements '
            '(e.g. android.widget.Button, XCUIElementTypeButton).',
      );
    if (withIndex) {
      argParser.addOption(
        'index',
        help: '0-based index among the matches, for an ambiguous selector.',
      );
    }
  }

  /// The selector options as tool arguments; [textKey] is the tool's name
  /// for the exact-text option.
  Map<String, Object?> selectorArgs(
    ArgResults results, {
    String textOption = 'text',
    String textKey = 'text',
    bool withIndex = true,
  }) =>
      {
        textKey: string(results, textOption),
        'textContains': string(results, 'text-contains'),
        'id': string(results, 'id'),
        'type': string(results, 'type'),
        if (withIndex) 'index': integer(results, 'index'),
      };

  /// Value of option [name] in [results], or null when not given. An empty
  /// value counts as not given unless [allowEmpty].
  String? string(ArgResults results, String name, {bool allowEmpty = false}) {
    final String? value;
    try {
      value = results[name] as String?;
    } on ArgumentError {
      // package:args checks `mandatory` only when the value is read.
      usageException('Missing required option --$name.');
    }
    return (value == null || (value.isEmpty && !allowEmpty)) ? null : value;
  }

  /// Integer value of option [name] in [results], or null when not given.
  int? integer(ArgResults results, String name) {
    final value = string(results, name);
    if (value == null) return null;
    return int.tryParse(value) ??
        usageException('--$name must be an integer, got "$value".');
  }

  /// Numeric value of option [name] in [results], or null when not given.
  num? number(ArgResults results, String name) {
    final value = string(results, name);
    if (value == null) return null;
    return num.tryParse(value) ??
        usageException('--$name must be a number, got "$value".');
  }

  /// Value of flag [name] in [results], or null when it was not given (the
  /// tool's default applies).
  bool? flag(ArgResults results, String name) =>
      results.wasParsed(name) ? results[name] as bool : null;

  /// [args] without the entries that were not given.
  static Map<String, dynamic> compact(Map<String, Object?> args) => {
        for (final entry in args.entries)
          if (entry.value != null) entry.key: entry.value,
      };
}

/// A double-quoted value, or a tool name (group 1) that starts a word of
/// prose (at the start, after a space or `(`). Selector values are quoted
/// (`id="native_tap"`), and a name inside an unquoted id
/// (`app:id/native_tap`, `login.native_tap`) does not start a word.
final _quotedOrToolName = RegExp(r'"[^"]*"|(?<=^|[\s(])(native_[a-z_]+)\b');

/// [text] from a shared MCP handler with tool names (`native_get_elements`)
/// replaced by the CLI commands (`native-get-elements`) of [commandNames].
/// Quoted values, ids and other words keep their `_`, and JSON output is
/// left as it is.
String cliText(String text, Set<String> commandNames) => text.startsWith('{')
    ? text
    : text.replaceAllMapped(_quotedOrToolName, (match) {
        final tool = match[1];
        if (tool == null) return match[0]!;
        final command = tool.replaceAll('_', '-');
        return commandNames.contains(command) ? command : tool;
      });

/// Opens a connector on the running server of [info], reusing its session
/// when the server still has it.
Future<WebDriverNativeConnector> attachNativeSession(NativeSessionInfo info) {
  final bootstrap = RunningServerBootstrap(Uri.parse(info.baseUrl));
  return switch (info.platform) {
    NativePlatform.android => AndroidNativeConnector.connect(
        serial: info.serial,
        bootstrap: bootstrap,
        sessionId: info.sessionId,
      ),
    NativePlatform.ios => IosNativeConnector.connect(
        udid: info.udid,
        bootstrap: bootstrap,
        sessionId: info.sessionId,
      ),
  };
}

/// The device-side server of a native session is not reachable.
class NativeSessionNotRunningException implements Exception {
  const NativeSessionNotRunningException(this.baseUrl);

  final Uri baseUrl;

  @override
  String toString() => 'No native server is running at $baseUrl.';
}

/// A server already running at [baseUrl]: never starts or stops anything.
class RunningServerBootstrap implements NativeServerBootstrap {
  RunningServerBootstrap(this.baseUrl);

  final Uri baseUrl;

  @override
  Future<Uri> ensureServerReady() async {
    final client = WebDriverClient(baseUrl.toString());
    try {
      if (await client.status()) return baseUrl;
    } catch (_) {
      // Reported below.
    } finally {
      client.close();
    }
    throw NativeSessionNotRunningException(baseUrl);
  }

  @override
  Future<void> dispose() async {}
}
