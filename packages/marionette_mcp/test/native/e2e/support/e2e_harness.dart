import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Where and what the device tests run against, from the environment:
///
/// - `MARIONETTE_E2E_PLATFORM`: `android` (default) or `ios`;
/// - `MARIONETTE_E2E_SERIAL` / `MARIONETTE_E2E_UDID`: the device, when
///   several are connected;
/// - `MARIONETTE_E2E_APP_ID`: the example app (default
///   `com.example.counter`), installed on the device;
/// - `MARIONETTE_E2E_VM_SERVICE_URI`: the app's VM service (`flutter run`),
///   for the scenarios that use the Flutter lane too — they are skipped
///   without it;
/// - `MARIONETTE_E2E_ARTIFACTS`: directory for the server log and, when a
///   scenario fails, a screenshot and the native tree (default: a temporary
///   directory, printed).
class E2eConfig {
  E2eConfig._({
    required this.platform,
    required this.serial,
    required this.udid,
    required this.appId,
    required this.vmServiceUri,
    required this.artifacts,
  });

  factory E2eConfig.fromEnvironment() {
    final env = Platform.environment;
    String? value(String key) {
      final raw = env[key];
      return (raw == null || raw.isEmpty) ? null : raw;
    }

    final artifacts = value('MARIONETTE_E2E_ARTIFACTS');
    return E2eConfig._(
      platform: value('MARIONETTE_E2E_PLATFORM') ?? 'android',
      serial: value('MARIONETTE_E2E_SERIAL'),
      udid: value('MARIONETTE_E2E_UDID'),
      appId: value('MARIONETTE_E2E_APP_ID') ?? 'com.example.counter',
      vmServiceUri: value('MARIONETTE_E2E_VM_SERVICE_URI'),
      artifacts: artifacts != null
          ? (Directory(artifacts)..createSync(recursive: true))
          : Directory.systemTemp.createTempSync('marionette_e2e_'),
    );
  }

  final String platform;
  final String? serial;
  final String? udid;
  final String appId;
  final String? vmServiceUri;
  final Directory artifacts;

  bool get isAndroid => platform == 'android';
  bool get isIos => platform == 'ios';

  /// `native_connect` arguments for this device.
  Map<String, dynamic> get connectArgs => {
        'platform': platform,
        if (serial != null) 'serial': serial,
        if (udid != null) 'udid': udid,
      };

  /// Starts the app, or brings its running instance to the front.
  Future<void> launchApp() => isAndroid
      ? _adb([
          'shell', 'monkey', '-p', appId, '-c', //
          'android.intent.category.LAUNCHER', '1',
        ])
      : _simctl(['launch', _simulator, appId]);

  /// Opens deep link [url] in the app.
  Future<void> openUrl(String url) => isAndroid
      ? _adb([
          'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', //
          '-d', "'$url'", appId,
        ])
      : _simctl(['openurl', _simulator, url]);

  /// Makes the app ask for the camera again. May terminate it.
  Future<void> resetCameraPermission() async {
    if (isIos)
      return _simctl(['privacy', _simulator, 'reset', 'camera', appId]);
    const camera = 'android.permission.CAMERA';
    await _adb(['shell', 'pm', 'revoke', appId, camera]);
    // Clears "don't ask again"; best-effort, older API levels lack it.
    await Process.run('adb', [
      if (serial != null) ...['-s', serial!],
      'shell', 'pm', 'clear-permission-flags', appId, camera, //
      'user-set', 'user-fixed',
    ]);
  }

  String get _simulator => udid ?? 'booted';

  Future<void> _adb(List<String> arguments) => _run('adb', [
        if (serial != null) ...['-s', serial!],
        ...arguments
      ]);

  Future<void> _simctl(List<String> arguments) =>
      _run('xcrun', ['simctl', ...arguments]);

  static Future<void> _run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    expect(
      result.exitCode,
      0,
      reason: '$executable ${arguments.join(' ')}: ${result.stderr}',
    );
  }
}

/// Result of one MCP tool call.
class ToolResult {
  ToolResult(this.isError, this.text, this.images);

  final bool isError;

  /// All text content, joined.
  final String text;

  /// Base64 PNGs.
  final List<String> images;

  Map<String, dynamic> get json => jsonDecode(text) as Map<String, dynamic>;

  @override
  String toString() => '${isError ? 'error' : 'ok'}: $text';
}

/// Drives the real MCP server ([bin/marionette_mcp.dart]) over stdio, like
/// an agent's MCP client.
class McpTestClient {
  McpTestClient._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .listen(_onLine);
    unawaited(_process.stderr.drain<void>());
  }

  final Process _process;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;

  /// Starts the server, logging to `server.log` in [logDir], and completes
  /// the MCP handshake.
  static Future<McpTestClient> start(Directory logDir) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/marionette_mcp.dart',
      '--log-level',
      'FINE',
      '--log-file',
      '${logDir.path}/server.log',
    ]);
    final client = McpTestClient._(process);
    await client._request('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'marionette-e2e', 'version': '1.0.0'},
    });
    client._send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    return client;
  }

  void _onLine(String line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    final id = message['id'];
    if (id is int) _pending.remove(id)?.complete(message);
  }

  void _send(Map<String, dynamic> message) =>
      _process.stdin.writeln(jsonEncode(message));

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = ++_nextId;
    final completer = _pending[id] = Completer<Map<String, dynamic>>();
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return completer.future.timeout(const Duration(minutes: 3));
  }

  /// Calls tool [name] and returns its result, errors included.
  Future<ToolResult> call(
    String name, [
    Map<String, dynamic> args = const {},
  ]) async {
    final response = await _request(
      'tools/call',
      {'name': name, 'arguments': args},
    );
    final error = response['error'];
    if (error != null) return ToolResult(true, jsonEncode(error), const []);
    final result = response['result'] as Map<String, dynamic>;
    final texts = <String>[];
    final images = <String>[];
    for (final content in result['content'] as List) {
      final map = content as Map<String, dynamic>;
      if (map['type'] == 'text') texts.add(map['text'] as String);
      if (map['type'] == 'image') images.add(map['data'] as String);
    }
    return ToolResult(result['isError'] == true, texts.join('\n'), images);
  }

  /// Calls tool [name] and fails the test when it reports an error.
  Future<ToolResult> ok(
    String name, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result = await call(name, args);
    if (result.isError) {
      fail('$name(${jsonEncode(args)}) failed: ${result.text}');
    }
    return result;
  }

  /// Closes stdin (the server exits on EOF) and waits for the process.
  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}

/// Runs [body]; when it fails, saves a screenshot and the native tree as
/// `<name>.png` / `<name>.json` in [config]'s artifacts directory, then
/// rethrows.
Future<void> withArtifacts(
  McpTestClient client,
  E2eConfig config,
  String name,
  Future<void> Function() body,
) async {
  try {
    await body();
  } catch (_) {
    final file = name.replaceAll(RegExp(r'[^\w-]+'), '_');
    try {
      final shot = await client.call('native_take_screenshot');
      if (shot.images.isNotEmpty) {
        File('${config.artifacts.path}/$file.png')
            .writeAsBytesSync(base64Decode(shot.images.first));
      }
      final tree = await client.call('native_get_elements');
      File('${config.artifacts.path}/$file.json').writeAsStringSync(tree.text);
    } catch (_) {
      // The original failure matters more than missing artifacts.
    }
    rethrow;
  }
}
