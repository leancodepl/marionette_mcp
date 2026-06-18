import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('stdio server process exits when stdin reaches EOF', () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'bin/marionette_mcp.dart'],
    );
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    // Closing the child's stdin is how an MCP host signals shutdown.
    await process.stdin.close();

    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        fail('Server did not exit within 30s of stdin closing');
      },
    );

    expect(exitCode, 0);
  });
}
