import 'dart:io';

import 'package:marionette_mcp/marionette_mcp.dart';
import 'package:test/test.dart';

void main() {
  ServerConfig parse(List<String> args) =>
      ServerConfig.fromResults(ServerConfig.buildParser().parse(args));

  test('retains stdio and logging defaults', () {
    final config = parse([]);
    expect(config.ssePort, isNull);
    expect(config.logLevel, 'INFO');
    expect(config.logFile, isNull);
  });

  test('parses the shared legacy SSE and logging options', () {
    final config =
        parse(['--sse-port', '8080', '-l', 'fine', '--log-file', 'log']);
    expect(config.ssePort, 8080);
    expect(config.logLevel, 'FINE');
    expect(config.logFile, 'log');
  });

  for (final port in ['typo', '-1', '65536', '1.5', '']) {
    test('rejects invalid SSE port "$port" instead of using stdio', () {
      expect(() => parse(['--sse-port=$port']), throwsFormatException);
    });
  }

  test('standalone executable reports an invalid port with a failing exit code',
      () async {
    final result = await Process.run(Platform.resolvedExecutable,
        ['run', 'bin/marionette_mcp.dart', '--sse-port=typo']);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('SSE port must be an integer'));
  });
}
