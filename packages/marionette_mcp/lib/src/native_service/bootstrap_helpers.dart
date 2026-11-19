import 'dart:async';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// Starts [executable] as a detached process that outlives this one.
Future<Process> startDetachedProcess(
  String executable,
  List<String> arguments,
) =>
    Process.start(executable, arguments, mode: ProcessStartMode.detached);

/// A started server process. Its output is drained, so a chatty process
/// cannot fill the OS pipe buffers and stall, and its exit code is kept.
final class ServerProcess {
  ServerProcess(Process process)
      : _process = process,
        _stdout = process.stdout.listen((_) {}),
        _stderr = process.stderr.listen((_) {}) {
    unawaited(process.exitCode.then((code) => _exitCode = code));
  }

  final Process _process;
  final StreamSubscription<List<int>> _stdout;
  final StreamSubscription<List<int>> _stderr;
  int? _exitCode;

  /// The exit code, once the process has ended.
  int? get exitCode => _exitCode;

  /// Completes with the exit code when the process ends.
  Future<int> get exited => _process.exitCode;

  /// Stops draining the output and sends [signal] to the process.
  Future<void> kill([ProcessSignal signal = ProcessSignal.sigterm]) async {
    await _stdout.cancel();
    await _stderr.cancel();
    _process.kill(signal);
  }
}

/// Whether a WebDriver server answers `/status` at [baseUrl], waiting at
/// most [shortTimeout] (see [WebDriverClient.status]).
Future<bool> isServerHealthy(
  String baseUrl, {
  Duration shortTimeout = webDriverShortTimeout,
}) async {
  final client = WebDriverClient(baseUrl, shortTimeout: shortTimeout);
  try {
    return await client.status();
  } finally {
    client.close();
  }
}

/// Polls `/status` of [client] every [pollInterval] until the server is
/// ready.
///
/// Throws the result of [exited] once [exitCode] reports that the server
/// process has ended, and the result of [timedOut] after [timeout].
Future<void> waitUntilHealthy(
  WebDriverClient client, {
  required Duration timeout,
  required Duration pollInterval,
  required int? Function() exitCode,
  required NativeBootstrapException Function(int exitCode) exited,
  required NativeBootstrapException Function() timedOut,
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (await client.status()) return;
    if (exitCode() case final code?) throw exited(code);
    await Future<void>.delayed(pollInterval);
  }
  throw timedOut();
}

/// The `marionette_mcp/<subdir>` cache directory: under `XDG_CACHE_HOME`,
/// else under `.cache` in `HOME` (or `USERPROFILE`), else under the system
/// temp directory.
Directory nativeCacheDir(String subdir, {Map<String, String>? environment}) {
  final variables = environment ?? Platform.environment;
  final xdgCache = variables['XDG_CACHE_HOME'];
  if (xdgCache != null && xdgCache.isNotEmpty) {
    return Directory('$xdgCache/marionette_mcp/$subdir');
  }
  final home = variables['HOME'] ?? variables['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    return Directory('$home/.cache/marionette_mcp/$subdir');
  }
  return Directory('${Directory.systemTemp.path}/marionette_mcp/$subdir');
}
