import 'dart:convert';
import 'dart:io';

/// Signature for running a short-lived process — injectable for testing.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

final _debuggerPortPattern = RegExp(r'--remote-debugging-port=(\d+)');

/// Resolves a Chrome DevTools `debuggerAddress` for attaching ChromeDriver
/// to an already-running browser (e.g. `flutter run -d chrome`).
///
/// Resolution order:
/// 1. Explicit [debuggerAddress] argument
/// 2. Env `MARIONETTE_CHROME_DEBUGGER_ADDRESS`
/// 3. Scan running Chrome/Chromium processes for `--remote-debugging-port`
/// 4. Probe common fixed ports (`9222`, `9223`) via CDP `/json/version`
Future<String?> resolveChromeDebuggerAddress({
  String? debuggerAddress,
  ProcessRunner? processRunner,
}) async {
  final explicit = debuggerAddress?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    return normalizeChromeDebuggerAddress(explicit);
  }

  final fromEnv =
      Platform.environment['MARIONETTE_CHROME_DEBUGGER_ADDRESS']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return normalizeChromeDebuggerAddress(fromEnv);
  }

  final fromProcess =
      await discoverChromeDebuggerPortFromProcesses(processRunner: processRunner);
  if (fromProcess != null) {
    return '127.0.0.1:$fromProcess';
  }

  for (final port in const [9222, 9223]) {
    if (await isChromeDebuggerReachable('127.0.0.1', port)) {
      return '127.0.0.1:$port';
    }
  }

  return null;
}

/// Normalizes user input to `host:port` (defaults host to `127.0.0.1`).
String normalizeChromeDebuggerAddress(String value) {
  final trimmed = value.trim();
  if (trimmed.contains(':')) return trimmed;
  return '127.0.0.1:$trimmed';
}

/// Returns the first `--remote-debugging-port` seen on a Chrome process line.
Future<int?> discoverChromeDebuggerPortFromProcesses({
  ProcessRunner? processRunner,
}) async {
  final run = processRunner ?? Process.run;
  final lines = await _processCommandLines(run);
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (!lower.contains('chrome') && !lower.contains('chromium')) continue;
    final match = _debuggerPortPattern.firstMatch(line);
    if (match != null) return int.tryParse(match.group(1)!);
  }
  return null;
}

Future<List<String>> _processCommandLines(ProcessRunner run) async {
  if (Platform.isWindows) {
    final result = await run('wmic', [
      'process',
      'where',
      "name='chrome.exe' or name='chromium.exe'",
      'get',
      'commandline',
    ]);
    if (result.exitCode != 0 || result.stdout is! String) return const [];
    return (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line != 'CommandLine')
        .toList();
  }

  final result = await run('ps', ['-ax', '-o', 'command=']);
  if (result.exitCode != 0 || result.stdout is! String) return const [];
  return (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// Returns true when Chrome CDP responds at `http://host:port/json/version`.
Future<bool> isChromeDebuggerReachable(String host, int port) async {
  final client = HttpClient();
  try {
    final request =
        await client.getUrl(Uri.parse('http://$host:$port/json/version'));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return false;
    final body = await utf8.decodeStream(response);
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> &&
        decoded['Browser'] is String &&
        (decoded['Browser'] as String).isNotEmpty;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Thrown when web native connect cannot attach and spawning was not requested.
class WebNativeAttachException implements Exception {
  const WebNativeAttachException(this.message);

  final String message;

  @override
  String toString() => 'WebNativeAttachException: $message';
}

const webNativeAttachInstructions = '''
Could not find a running Chrome to attach (no debuggerAddress and auto-discovery failed).

When using Flutter web alongside the Marionette Flutter lane, start Chrome with a fixed CDP port, then call native_connect:

  flutter run -d chrome \\
    --web-browser-debug-port=9222 \\
    --web-browser-flag=--remote-allow-origins=*

Then either pass debuggerAddress: "127.0.0.1:9222" to native_connect, or set:

  export MARIONETTE_CHROME_DEBUGGER_ADDRESS=127.0.0.1:9222
''';
