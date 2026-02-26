import 'package:marionette_cli/src/cli/marionette_command_runner.dart';
import 'package:test/test.dart';

void main() {
  late MarionetteCommandRunner runner;

  setUp(() {
    runner = MarionetteCommandRunner();
  });

  group('MarionetteCommandRunner', () {
    test('no command prints usage and returns 0', () async {
      final exitCode = await runner.run([]);
      expect(exitCode, equals(0));
    });

    test('unknown command prints usage and returns 0', () async {
      final exitCode = await runner.run(['nonexistent']);
      expect(exitCode, equals(0));
    });

    test('all expected commands are registered', () {
      final commandNames = runner.commands.keys.toSet();

      const expected = {
        'register',
        'unregister',
        'list',
        'get-interactive-elements',
        'tap',
        'enter-text',
        'scroll-to',
        'take-screenshots',
        'get-logs',
        'hot-reload',
        'doctor',
        'help-ai',
        'mcp',
        'help',
      };

      expect(commandNames, equals(expected));
    });

    test('register with missing args returns 64', () async {
      final exitCode = await runner.run(['register']);
      expect(exitCode, equals(64));
    });

    test('unregister with no args returns 64', () async {
      final exitCode = await runner.run(['unregister']);
      expect(exitCode, equals(64));
    });

    test('mutually exclusive --instance and --uri returns 64', () async {
      final exitCode = await runner.run([
        '-i',
        'foo',
        '--uri',
        'ws://127.0.0.1:8181/ws',
        'tap',
        '--key',
        'k',
      ]);
      expect(exitCode, equals(64));
    });

    test('help-ai returns 0 without --instance or --uri', () async {
      final exitCode = await runner.run(['help-ai']);
      expect(exitCode, equals(0));
    });

    test('list returns 0 with empty registry', () async {
      final exitCode = await runner.run(['list']);
      expect(exitCode, equals(0));
    });
  });
}
