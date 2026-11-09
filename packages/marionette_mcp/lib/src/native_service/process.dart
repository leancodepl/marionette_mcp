import 'dart:io';

/// Signature for running a short-lived process — injectable for testing.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Signature for starting a long-running process — injectable for testing.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// A process that exited with a non-zero code.
class ProcessCommandException implements Exception {
  const ProcessCommandException(this.command, this.exitCode, this.output);

  /// The full command line, for diagnostics.
  final String command;
  final int exitCode;

  /// Trimmed stderr, or stdout when stderr is empty.
  final String output;

  @override
  String toString() =>
      '$command failed (exit $exitCode)${output.isEmpty ? '' : ': $output'}';
}

/// Returns the stdout of [result] as a string.
String processStdout(ProcessResult result) =>
    result.stdout is String ? result.stdout as String : '${result.stdout}';

/// Returns the most useful diagnostic text from [result]: trimmed stderr,
/// else trimmed stdout, else the exit code.
String processMessage(ProcessResult result) {
  final stderr =
      result.stderr is String ? (result.stderr as String).trim() : '';
  final stdout = processStdout(result).trim();
  if (stderr.isNotEmpty) return stderr;
  if (stdout.isNotEmpty) return stdout;
  return 'process exited with code ${result.exitCode}';
}

/// Throws [ProcessCommandException] when [result] has a non-zero exit code.
void checkProcessResult(
  ProcessResult result,
  String executable,
  List<String> arguments,
) {
  if (result.exitCode == 0) return;
  throw ProcessCommandException(
    [executable, ...arguments].join(' '),
    result.exitCode,
    processMessage(result),
  );
}

/// Whether local [port] is free for a server on the loopback interface: it
/// can be bound, and nothing answers a connection to it. Binding alone is not
/// enough — on macOS 127.0.0.1 can be bound while a dual-stack listener
/// (IPv6 `*`, e.g. `python3 -m http.server`) takes its connections.
Future<bool> canBindLoopbackPort(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
  } on SocketException {
    return false;
  }
  try {
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(milliseconds: 500),
    );
    client.destroy();
    return false;
  } on SocketException {
    return true;
  }
}
