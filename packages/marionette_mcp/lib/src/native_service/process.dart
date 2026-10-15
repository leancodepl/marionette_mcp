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
