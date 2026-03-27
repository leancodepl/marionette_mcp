import 'dart:io';

/// Signature for running a process — injectable for testing.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Result of an ADB operation.
class AdbResult {
  const AdbResult({required this.success, this.stderr = ''});
  final bool success;
  final String stderr;
}

/// Manages ADB reverse tunnel setup and teardown.
class AdbHelper {
  AdbHelper({ProcessRunner? processRunner})
    : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  /// Checks whether `adb` is available on PATH.
  Future<bool> isAvailable() async {
    try {
      final result = await _run('adb', ['version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Sets up `adb reverse tcp:$port tcp:$port`.
  Future<AdbResult> setupReverse(int port) async {
    final result = await _run('adb', ['reverse', 'tcp:$port', 'tcp:$port']);
    return AdbResult(
      success: result.exitCode == 0,
      stderr: (result.stderr as String).trim(),
    );
  }

  /// Removes `adb reverse` mapping. Best-effort — does not throw.
  Future<AdbResult> removeReverse(int port) async {
    try {
      final result = await _run('adb', ['reverse', '--remove', 'tcp:$port']);
      return AdbResult(
        success: result.exitCode == 0,
        stderr: (result.stderr as String).trim(),
      );
    } catch (_) {
      return const AdbResult(success: false, stderr: 'Process failed');
    }
  }
}
