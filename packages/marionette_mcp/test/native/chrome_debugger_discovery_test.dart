import 'dart:io';

import 'package:marionette_mcp/src/native_service/chrome_debugger_discovery.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeChromeDebuggerAddress', () {
    test('adds localhost host when only port is given', () {
      expect(normalizeChromeDebuggerAddress('9222'), '127.0.0.1:9222');
    });

    test('preserves host:port form', () {
      expect(
        normalizeChromeDebuggerAddress('127.0.0.1:9222'),
        '127.0.0.1:9222',
      );
    });
  });

  group('discoverChromeDebuggerPortFromProcesses', () {
    test('parses remote-debugging-port from ps output', () async {
      final port = await discoverChromeDebuggerPortFromProcesses(
        processRunner: (_, __) async => ProcessResult(
          0,
          0,
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome '
          '--remote-debugging-port=54321 --user-data-dir=/tmp/flutter_tools',
          '',
        ),
      );
      expect(port, 54321);
    });
  });

  group('resolveChromeDebuggerAddress', () {
    test('prefers explicit debuggerAddress', () async {
      expect(
        await resolveChromeDebuggerAddress(
          debuggerAddress: '127.0.0.1:7777',
          processRunner: (_, __) async =>
              throw StateError('should not scan processes'),
        ),
        '127.0.0.1:7777',
      );
    });
  });
}
