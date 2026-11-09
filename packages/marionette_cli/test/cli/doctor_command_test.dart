import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/commands/doctor_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:test/test.dart';

/// Collects what a command writes to stdout or stderr.
class _CapturedOutput implements Stdout {
  final text = StringBuffer();

  @override
  void write(Object? object) => text.write(object);

  @override
  void writeln([Object? object = '']) => text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('doctor gives connect the --timeout and reports why it timed out',
      () async {
    // A VM service that accepts the connection and never answers.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      (await WebSocketTransformer.upgrade(request)).listen((_) {});
    });
    final home = await Directory.systemTemp.createTemp('marionette_doctor');
    addTearDown(() => home.delete(recursive: true));
    final registry = InstanceRegistry(baseDir: home.path);
    await registry.register('silent', 'ws://127.0.0.1:${server.port}/ws');
    final runner = CommandRunner<int>('marionette', '')
      ..argParser.addOption('timeout')
      ..addCommand(DoctorCommand(registry));
    final errors = _CapturedOutput();

    final exitCode = await IOOverrides.runZoned(
      () => runner.run(['--timeout', '1', 'doctor']),
      stdout: () => _CapturedOutput(),
      stderr: () => errors,
    );

    expect(exitCode, 1);
    expect(
      errors.text.toString(),
      contains('Timed out connecting to the VM service at '
          'ws://127.0.0.1:${server.port}/ws after 1s'),
    );
  });
}
