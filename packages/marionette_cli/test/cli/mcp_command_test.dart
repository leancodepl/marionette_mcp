import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/commands/mcp_command.dart';
import 'package:test/test.dart';

void main() {
  /// The `enableNativeLane` that `marionette` with [args] runs the server
  /// with.
  Future<bool?> nativeLaneOf(List<String> args) async {
    bool? nativeLane;
    final runner = CommandRunner<int>('marionette', '')
      ..addCommand(
        McpCommand(
          runServer: ({
            required logLevel,
            required enableNativeLane,
            logFile,
            ssePort,
          }) async {
            nativeLane = enableNativeLane;
            return 0;
          },
        ),
      );
    await runner.run(args);
    return nativeLane;
  }

  test('runs the server with the native lane by default', () async {
    expect(await nativeLaneOf(['mcp']), isTrue);
  });

  test('--no-native runs the server without the native lane', () async {
    expect(await nativeLaneOf(['mcp', '--no-native']), isFalse);
  });
}
