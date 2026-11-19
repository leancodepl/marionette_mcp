import 'dart:io';

import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// Starts [executable] as a detached process that outlives this one.
Future<Process> startDetachedProcess(
  String executable,
  List<String> arguments,
) =>
    Process.start(executable, arguments, mode: ProcessStartMode.detached);

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
