import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/marionette_mcp.dart';
import 'package:marionette_mcp/src/mcp/server_runner.dart' show ExitSignal;
import 'package:test/test.dart';

void main() {
  test('runner reports log setup failure with a failing result', () async {
    final directory = await Directory.systemTemp.createTemp('runner-log-');
    addTearDown(() => directory.delete(recursive: true));

    // A directory cannot be opened as the log file. This fails before any
    // transport starts, so the public runner must report the startup failure.
    expect(
      await runMcpServer(logLevel: 'INFO', logFile: directory.path),
      1,
    );
  });

  test('SSE bind failure returns a failing result and cancels logging',
      () async {
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => listener.close(force: true));
    final directory = await Directory.systemTemp.createTemp('runner-bind-');
    addTearDown(() => directory.delete(recursive: true));
    final log = File('${directory.path}/server.log');

    expect(
      await runMcpServer(
        logLevel: 'INFO',
        logFile: log.path,
        ssePort: listener.port,
      ),
      1,
    );
    final before = log.readAsStringSync();
    expect(before, contains('Error when running MCP server'));
    logging.Logger('runner-test').severe('after runner completion');
    expect(log.readAsStringSync(), before);

    // The executable must also drain its signal subscriptions on startup
    // failure, exit promptly, and keep diagnostics off the JSON-RPC channel.
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'bin/marionette_mcp.dart',
      '--sse-port',
      '${listener.port}',
      '--log-level',
      'SEVERE',
    ]);
    addTearDown(process.kill);
    final output = process.stdout.toList();
    final errors = process.stderr.toList();
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 1);
    expect(await output, isEmpty);
    expect(await errors, isNotEmpty);
  });

  test('signal owner disposal is idempotent', () {
    final signal = ExitSignal();
    signal.dispose();
    signal.dispose();
  });
}
