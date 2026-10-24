import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Owns subprocess streams and guarantees cleanup even when an assertion fails.
class TestProcess {
  TestProcess(this.process)
      : lines = StreamIterator(
          process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        ) {
    _stderr = process.stderr.transform(utf8.decoder).listen((message) {
      errors.write(message);
      _errorEvents.add(message);
    });
  }

  final Process process;
  final StreamIterator<String> lines;
  final errors = StringBuffer();
  final _errorEvents = StreamController<String>.broadcast();
  late final StreamSubscription<String> _stderr;

  static Future<TestProcess> start(List<String> arguments) async =>
      TestProcess(await Process.start(Platform.resolvedExecutable, arguments));

  Future<void> waitForStderr(String text) async {
    if (errors.toString().contains(text)) return;
    await _errorEvents.stream
        .firstWhere((_) => errors.toString().contains(text))
        .timeout(const Duration(seconds: 15));
  }

  Future<int> exitCodeWithin(Duration timeout) => process.exitCode.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Child did not exit. Stderr: $errors',
          timeout,
        ),
      );

  void send(Map<String, Object?> message) {
    process.stdin.writeln(jsonEncode(message));
  }

  Future<String> vmServiceUri() => _vmServiceUri().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'VM fixture did not become ready: $errors',
        ),
      );

  Future<String> _vmServiceUri() async {
    while (await lines.moveNext()) {
      final line = lines.current;
      if (line.startsWith('READY:')) return line.substring('READY:'.length);
    }
    throw StateError('VM fixture exited before becoming ready: $errors');
  }

  Future<Map<String, dynamic>> response(int id) => _response(id).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'MCP server did not respond to request $id: $errors',
        ),
      );

  Future<Map<String, dynamic>> _response(int id) async {
    while (await lines.moveNext()) {
      final message = jsonDecode(lines.current) as Map<String, dynamic>;
      if (message['id'] == id) return message;
    }
    throw StateError('MCP server exited before responding to $id: $errors');
  }

  Future<void> dispose() async {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } finally {
      await lines.cancel();
      await _stderr.cancel();
      await _errorEvents.close();
      try {
        await process.stdin.close();
      } on IOException {
        // The process may already have closed its input pipe.
      }
    }
  }
}
