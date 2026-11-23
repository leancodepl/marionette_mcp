import 'dart:convert';
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

/// Serves the replies of an app with marionette_flutter whose configuration
/// declares [uiLibraries], enough for connect and inspectUiSupport. With
/// [answerExtensions] false, it leaves service extension calls unanswered,
/// as an app paused at a breakpoint does.
Future<HttpServer> _startApp({
  List<String> uiLibraries = const [],
  bool answerExtensions = true,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  const isolateRef = {
    'type': '@Isolate',
    'id': 'isolates/1',
    'number': '1',
    'name': 'main',
    'isSystemIsolate': false,
  };
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final method = message['method'] as String;
      if (!answerExtensions && method.startsWith('ext.')) return;
      final result = switch (method) {
        'getVM' => {
            'type': 'VM',
            'isolates': [isolateRef]
          },
        'getIsolate' => {
            ...isolateRef,
            'type': 'Isolate',
            'libraries': <Object>[],
            'extensionRPCs': [
              'ext.flutter.marionette.getLogs',
              'ext.flutter.marionette.getConfiguration',
            ],
          },
        'ext.flutter.marionette.getConfiguration' => {
            'type': '_ext',
            'uiLibraries': uiLibraries,
          },
        _ => {'type': 'Success'},
      };
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': message['id'],
        'result': result,
      }));
    });
  });
  return server;
}

void main() {
  late InstanceRegistry registry;
  late CommandRunner<int> runner;

  setUp(() async {
    final home = await Directory.systemTemp.createTemp('marionette_doctor');
    addTearDown(() => home.delete(recursive: true));
    registry = InstanceRegistry(baseDir: home.path);
    runner = CommandRunner<int>('marionette', '')
      ..argParser.addOption('timeout')
      ..argParser.addOption('instance', abbr: 'i')
      ..addCommand(DoctorCommand(registry));
  });

  group('--required-ui-library', () {
    test('needs --instance', () async {
      await expectLater(
        runner.run(['doctor', '--required-ui-library', 'material_ui']),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects an unregistered instance', () async {
      await expectLater(
        runner.run(['-i', 'gone', 'doctor']),
        throwsA(isA<UsageException>()),
      );
    });

    test('checks only that instance and fails on a missing integration',
        () async {
      final app = await _startApp(uiLibraries: ['material_ui']);
      addTearDown(() => app.close(force: true));
      await registry.register('shop', 'ws://127.0.0.1:${app.port}/ws');
      await registry.register('stopped', 'ws://127.0.0.1:1/ws');
      final output = _CapturedOutput();

      final exitCode = await IOOverrides.runZoned(
        () => runner.run([
          '-i',
          'shop',
          'doctor',
          '--required-ui-library',
          'material_ui',
          '--required-ui-library',
          'cupertino_ui',
        ]),
        stdout: () => output,
        stderr: () => _CapturedOutput(),
      );

      expect(exitCode, 1);
      expect(
        output.text.toString(),
        allOf(
          contains('flutter pub add marionette_cupertino'),
          isNot(contains('stopped')),
        ),
      );
    });

    test('fails when the UI integration check cannot run', () async {
      final app = await _startApp(answerExtensions: false);
      addTearDown(() => app.close(force: true));
      await registry.register('paused', 'ws://127.0.0.1:${app.port}/ws');
      final errors = _CapturedOutput();

      final exitCode = await IOOverrides.runZoned(
        () => runner.run([
          '--timeout',
          '1',
          '-i',
          'paused',
          'doctor',
          '--required-ui-library',
          'material_ui',
        ]),
        stdout: () => _CapturedOutput(),
        stderr: () => errors,
      ).timeout(const Duration(seconds: 5));

      expect(exitCode, 1);
      expect(errors.text.toString(), contains('could not be checked'));
    });
  });

  test('doctor gives connect the --timeout and reports why it timed out',
      () async {
    // A VM service that accepts the connection and never answers.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      (await WebSocketTransformer.upgrade(request)).listen((_) {});
    });
    await registry.register('silent', 'ws://127.0.0.1:${server.port}/ws');
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

  test('doctor gives the UI integration check the --timeout and goes on',
      () async {
    final app = await _startApp(answerExtensions: false);
    addTearDown(() => app.close(force: true));
    await registry.register('paused', 'ws://127.0.0.1:${app.port}/ws');
    final output = _CapturedOutput();
    final errors = _CapturedOutput();

    final exitCode = await IOOverrides.runZoned(
      () => runner.run(['--timeout', '1', 'doctor']),
      stdout: () => output,
      stderr: () => errors,
    ).timeout(const Duration(seconds: 5));

    expect(exitCode, 0);
    expect(output.text.toString(), contains('All instances are reachable.'));
    expect(errors.text.toString(), contains('could not be checked'));
  });
}
