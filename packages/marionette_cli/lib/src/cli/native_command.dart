import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Name of the native session used when `--native-session` is not given.
const defaultNativeSession = 'default';

/// Reads the `--native-session` global option.
String nativeSessionName(ArgResults? globalResults) {
  final raw = globalResults?['native-session'] as String?;
  return (raw != null && raw.isNotEmpty) ? raw : defaultNativeSession;
}

/// Base class for commands that run a native-lane MCP tool against the
/// session started by `native-connect`.
///
/// Each command parses its options into the tool's arguments and calls the
/// same handler as the MCP tool, so behaviour, validation and messages are
/// shared. The device-side server keeps running between commands and the
/// WebDriver session is reused (docs/native-lane-decisions.md#d4).
abstract class NativeCommand extends Command<int> {
  NativeSessionRegistry get nativeRegistry;

  /// Runs the shared MCP handler with [args] against [context].
  Future<CallToolResult> execute(
    NativeServiceContext context,
    Map<String, dynamic> args,
  );

  /// The tool arguments from the command line; throws a usage error for
  /// malformed values.
  Map<String, dynamic> toolArguments();

  /// Flutter view metrics for commands that bridge to the Flutter lane.
  Future<Map<String, dynamic>> Function()? get flutterViewMetrics => null;

  /// Saves an image returned by the tool. Commands without image output
  /// report that it was dropped.
  Future<void> saveImage(ImageContent image) async {
    stderr.writeln('(image output not saved)');
  }

  /// Releases anything [flutterViewMetrics] opened.
  Future<void> cleanup() async {}

  @override
  Future<int> run() async {
    final args = toolArguments();
    final viewMetrics = flutterViewMetrics;
    final name = nativeSessionName(globalResults);
    final info = nativeRegistry.get(name);
    if (info == null) {
      stderr.writeln(
        'No native session "$name". Start one with: marionette '
        '${name == defaultNativeSession ? '' : '--native-session $name '}'
        'native-connect --platform android|ios',
      );
      return 1;
    }
    final platform = NativePlatform.tryParse(info.platform);
    if (platform == null) {
      stderr.writeln('Native session "$name" has an unknown platform '
          '"${info.platform}". Run native-connect again.');
      return 1;
    }

    final WebDriverNativeConnector connector;
    try {
      connector = await attachNativeSession(info, platform);
    } on NativeSessionNotRunningException catch (e) {
      stderr.writeln(
        'The native server of session "$name" (${info.device}) is not '
        'running at ${e.baseUrl}: the device or simulator was restarted, or '
        'the server was stopped.\n'
        'Hint: Run "marionette native-connect" again.',
      );
      return 1;
    } catch (e) {
      stderr.writeln('Could not attach to native session "$name": $e');
      return 1;
    }

    final context = NativeServiceContext(flutterViewMetrics: viewMetrics)
      ..connector = connector
      ..platform = platform
      ..defaultAppId = info.defaultAppId;
    try {
      final result = await execute(context, args);
      return await _print(result);
    } finally {
      info
        ..sessionId = connector.sessionId
        ..defaultAppId = context.defaultAppId ?? info.defaultAppId;
      nativeRegistry.save(info);
      connector.release();
      await cleanup();
    }
  }

  Future<int> _print(CallToolResult result) async {
    final isError = result.isError;
    for (final content in result.content) {
      if (content is TextContent) {
        (isError ? stderr : stdout).writeln(cliText(content.text));
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
        help: 'Resource id (Android) or accessibility identifier (iOS).',
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
  Map<String, Object?> selectorArgs({
    String textOption = 'text',
    String textKey = 'text',
    bool withIndex = true,
  }) =>
      {
        textKey: string(textOption),
        'textContains': string('text-contains'),
        'id': string('id'),
        'type': string('type'),
        if (withIndex) 'index': integer('index'),
      };

  ArgResults? _parsedForTest;

  /// [toolArguments] for [results] parsed by this command's [argParser] —
  /// lets tests check the mapping to the MCP tool without a runner.
  Map<String, dynamic> argumentsFor(ArgResults results) {
    _parsedForTest = results;
    try {
      return toolArguments();
    } finally {
      _parsedForTest = null;
    }
  }

  ArgResults? get _results => _parsedForTest ?? argResults;

  /// Value of option [name], or null when not given.
  String? string(String name) {
    final value = _results?[name] as String?;
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Integer value of option [name], or null when not given.
  int? integer(String name) {
    final value = string(name);
    if (value == null) return null;
    return int.tryParse(value) ??
        usageException('--$name must be an integer, got "$value".');
  }

  /// Numeric value of option [name], or null when not given.
  num? number(String name) {
    final value = string(name);
    if (value == null) return null;
    return num.tryParse(value) ??
        usageException('--$name must be a number, got "$value".');
  }

  /// Value of flag [name], or null when it was not given (the tool's
  /// default applies).
  bool? flag(String name) {
    final results = _results;
    if (results == null || !results.wasParsed(name)) return null;
    return results[name] as bool;
  }

  /// JSON object value of option [name], or null when not given.
  Map<String, dynamic>? jsonObject(String name) {
    final value = string(name);
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
    usageException('--$name must be a JSON object, got "$value".');
  }

  /// [args] without the entries that were not given.
  static Map<String, dynamic> compact(Map<String, Object?> args) => {
        for (final entry in args.entries)
          if (entry.value != null) entry.key: entry.value,
      };
}

final _toolName = RegExp(r'\bnative_[a-z_]+\b');

/// [text] from a shared MCP handler with tool names (`native_get_elements`)
/// replaced by the CLI commands (`native-get-elements`). JSON output is left
/// as it is.
String cliText(String text) => text.startsWith('{')
    ? text
    : text.replaceAllMapped(
        _toolName,
        (match) => match[0]!.replaceAll('_', '-'),
      );

/// Opens a connector on the running server of [info], reusing its session
/// when the server still has it.
Future<WebDriverNativeConnector> attachNativeSession(
  NativeSessionInfo info,
  NativePlatform platform,
) {
  final bootstrap = RunningServerBootstrap(Uri.parse(info.baseUrl));
  return switch (platform) {
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
