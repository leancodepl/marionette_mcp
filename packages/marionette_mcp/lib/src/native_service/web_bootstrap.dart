import 'dart:async';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/android_bootstrap.dart'
    show ProcessRunner, ProcessStarter;
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// Failure stage while preparing ChromeDriver.
enum WebBootstrapFailure {
  chromeDriverMissing,
  startFailed,
  healthCheck,
}

/// A failure while preparing the local ChromeDriver server.
class WebBootstrapException implements Exception {
  const WebBootstrapException(this.failure, this.message);

  final WebBootstrapFailure failure;
  final String message;

  @override
  String toString() => 'WebBootstrapException($failure): $message';
}

/// Starts (or attaches to) ChromeDriver and returns its local WebDriver URL.
///
/// Resolution order for the binary:
/// 1. Explicit [chromeDriverPath]
/// 2. Env `MARIONETTE_CHROMEDRIVER`
/// 3. `chromedriver` on PATH
///
/// When [existingServerUrl] is set, no process is started — the URL is
/// health-checked and returned as-is (attach mode).
class WebBootstrap {
  WebBootstrap({
    this.chromeDriverPath,
    this.existingServerUrl,
    this.localPort,
    ProcessRunner? processRunner,
    ProcessStarter? processStarter,
  })  : _run = processRunner ?? Process.run,
        _start =
            processStarter ?? (processRunner == null ? Process.start : null);

  /// Optional path/name of the chromedriver executable.
  final String? chromeDriverPath;

  /// When set, skip spawning chromedriver and use this base URL.
  final String? existingServerUrl;

  /// Preferred local port. When null, a free port is chosen.
  final int? localPort;

  final ProcessRunner _run;
  final ProcessStarter? _start;

  Process? _process;
  WebDriverClient? _healthClient;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Uri? _readyUri;

  /// Ensures ChromeDriver is reachable and returns its base URI.
  Future<Uri> ensureServerReady() async {
    final readyUri = _readyUri;
    final existingClient = _healthClient;
    if (readyUri != null &&
        existingClient != null &&
        await existingClient.status()) {
      return readyUri;
    }

    final attach = existingServerUrl?.trim();
    if (attach != null && attach.isNotEmpty) {
      final baseUri = Uri.parse(attach);
      _healthClient = WebDriverClient(baseUri.toString());
      await _waitUntilHealthy(_healthClient!);
      _readyUri = baseUri;
      return baseUri;
    }

    try {
      final executable = await _resolveExecutable();
      final port = localPort ?? await _pickFreePort();
      await _startChromeDriver(executable, port);

      final baseUri = Uri.parse('http://127.0.0.1:$port');
      _healthClient = WebDriverClient(baseUri.toString());
      await _waitUntilHealthy(_healthClient!);
      _readyUri = baseUri;
      return baseUri;
    } on WebBootstrapException {
      await dispose();
      rethrow;
    } catch (error) {
      await dispose();
      throw WebBootstrapException(
        WebBootstrapFailure.startFailed,
        'Failed to start ChromeDriver: $error',
      );
    }
  }

  /// Stops the ChromeDriver process (if owned) and closes health clients.
  Future<void> dispose() async {
    _readyUri = null;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _healthClient?.close();
    _healthClient = null;

    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        // Best-effort.
      }
    }
  }

  Future<String> _resolveExecutable() async {
    final candidates = <String>[
      if (chromeDriverPath != null && chromeDriverPath!.trim().isNotEmpty)
        chromeDriverPath!.trim(),
      if ((Platform.environment['MARIONETTE_CHROMEDRIVER'] ?? '')
          .trim()
          .isNotEmpty)
        Platform.environment['MARIONETTE_CHROMEDRIVER']!.trim(),
      'chromedriver',
    ];

    for (final candidate in candidates) {
      if (candidate.contains('/') || candidate.contains('\\')) {
        if (File(candidate).existsSync()) return candidate;
        continue;
      }
      final probe = await _run(
        Platform.isWindows ? 'where' : 'which',
        [candidate],
      );
      if (probe.exitCode == 0) {
        final out = (probe.stdout as String).trim().split('\n').first.trim();
        if (out.isNotEmpty) return out;
      }
    }

    throw const WebBootstrapException(
      WebBootstrapFailure.chromeDriverMissing,
      'chromedriver not found. Install ChromeDriver and ensure it is on PATH, '
      'or set MARIONETTE_CHROMEDRIVER to the binary path.',
    );
  }

  Future<void> _startChromeDriver(String executable, int port) async {
    final starter = _start;
    if (starter == null) {
      throw const WebBootstrapException(
        WebBootstrapFailure.startFailed,
        'No ProcessStarter available to launch ChromeDriver '
        '(inject processStarter when using a custom ProcessRunner).',
      );
    }

    try {
      _process = await starter(executable, [
        '--port=$port',
        '--allowed-ips=',
      ]);
    } catch (error) {
      throw WebBootstrapException(
        WebBootstrapFailure.startFailed,
        'Could not launch "$executable": $error',
      );
    }

    _stdoutSub = _process!.stdout.listen((_) {});
    _stderrSub = _process!.stderr.listen((_) {});
  }

  Future<void> _waitUntilHealthy(WebDriverClient client) async {
    const timeout = Duration(seconds: 30);
    const interval = Duration(milliseconds: 250);
    final deadline = DateTime.now().add(timeout);
    var processExited = false;
    final process = _process;
    if (process != null) {
      unawaited(process.exitCode.then((_) => processExited = true));
    }

    while (DateTime.now().isBefore(deadline)) {
      if (await client.status()) return;
      if (processExited) {
        throw const WebBootstrapException(
          WebBootstrapFailure.startFailed,
          'ChromeDriver exited before becoming ready',
        );
      }
      await Future<void>.delayed(interval);
    }

    throw WebBootstrapException(
      WebBootstrapFailure.healthCheck,
      'ChromeDriver did not become ready within ${timeout.inSeconds}s',
    );
  }

  static Future<int> _pickFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}
