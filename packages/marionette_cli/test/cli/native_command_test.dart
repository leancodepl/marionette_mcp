import 'dart:convert';
import 'dart:io';

import 'package:marionette_cli/src/cli/commands/native_session_commands.dart';
import 'package:marionette_cli/src/cli/marionette_command_runner.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:test/test.dart';

const _source = '<hierarchy>'
    '<node class="android.widget.Button" text="Allow" clickable="true" '
    'bounds="[0,0][100,50]"/>'
    '</hierarchy>';

/// A valid 1x1 PNG, base64-encoded.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  late Directory tempDir;
  late NativeSessionRegistry nativeRegistry;
  late _FakeWebDriver server;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('marionette_native_cmd_');
    nativeRegistry = NativeSessionRegistry(baseDir: '${tempDir.path}/native');
    server = await _FakeWebDriver.start();
  });

  tearDown(() async {
    await server.close();
    tempDir.deleteSync(recursive: true);
  });

  void saveSession({
    String? sessionId,
    String name = 'default',
    String? baseUrl,
    bool startedServer = false,
  }) =>
      nativeRegistry.save(
        NativeSessionInfo(
          name: name,
          platform: NativePlatform.android,
          baseUrl: baseUrl ?? server.baseUrl,
          createdAt: DateTime.utc(2026, 10, 20),
          serial: 'test-serial',
          sessionId: sessionId,
          startedServer: startedServer,
        ),
      );

  Future<_Run> run(
    List<String> args, {
    String? operatingSystem,
    Map<String, String> environment = const {},
  }) async {
    final out = _CapturingStdout();
    final err = _CapturingStdout();
    final code = await IOOverrides.runZoned(
      () => MarionetteCommandRunner(
        registry: InstanceRegistry(baseDir: '${tempDir.path}/instances'),
        nativeRegistry: nativeRegistry,
        operatingSystem: operatingSystem,
        environment: environment,
      ).run(args),
      stdout: () => out,
      stderr: () => err,
      getCurrentDirectory: () => tempDir,
    );
    return (code: code, out: out.text, err: err.text);
  }

  test('without a session, says how to start one', () async {
    final result = await run(['native-tap', '--text', 'Allow']);

    expect(result.code, 1);
    expect(result.err, contains('marionette native-connect --platform'));
  });

  test('a named session is used and named in the hint', () async {
    final result = await run(
      ['--native-device', 'pixel', 'native-tap', '--text', 'Allow'],
    );

    expect(result.err, contains('--native-device pixel native-connect'));
  });

  test('malformed values are usage errors', () async {
    saveSession();

    expect((await run(['native-tap', '--index', 'two'])).code, 64);
    expect((await run(['native-press-key', '--key', 'f13'])).code, 64);
    expect(
      (await run(['native-notifications', '--action', 'push'])).code,
      64,
    );
  });

  test('a missing required option is a usage error, not a crash', () async {
    saveSession();

    for (final args in [
      ['native-enter-text', 'positional'],
      ['native-press-key'],
      ['native-notifications'],
      ['native-scroll', '--text', 'Row'],
      ['native-swipe', '--start-x', '1'],
    ]) {
      final result = await run(args);

      expect(result.code, 64, reason: '$args');
      expect(result.err, contains('Missing required option --'),
          reason: '$args');
    }
  });

  test('a screenshot without --output fails before any device call', () async {
    saveSession(sessionId: 'kept');

    final result = await run(['native-take-screenshot']);

    expect(result.code, 64);
    expect(result.err, contains('Missing required option --output.'));
    expect(server.requests, isEmpty);
  });

  test('reuses the saved WebDriver session and keeps it', () async {
    saveSession(sessionId: 'kept');
    server
      ..on('GET', '/session/kept/orientation', 'PORTRAIT')
      ..on('GET', '/session/kept/source', _source);

    final result = await run(
      ['native-get-elements', '--no-include-foreground-app'],
    );

    expect(result.code, 0, reason: result.err);
    final payload = jsonDecode(result.out) as Map<String, dynamic>;
    expect((payload['elements'] as List).single['text'], 'Allow');
    expect(server.requests, isNot(contains('POST /session')));
    expect(server.requests, isNot(contains('DELETE /session/kept')));
    expect(nativeRegistry.get('default')!.sessionId, 'kept');
  });

  test('replaces a session the server no longer has and saves it', () async {
    saveSession(sessionId: 'gone');
    server
      ..on('POST', '/session', {'sessionId': 'fresh', 'capabilities': {}})
      ..on('POST', '/session/fresh/appium/settings', null)
      ..on('GET', '/session/fresh/source', _source);

    final result = await run(
      ['native-get-elements', '--no-include-foreground-app'],
    );

    expect(result.code, 0, reason: result.err);
    expect(nativeRegistry.get('default')!.sessionId, 'fresh');
  });

  group('a session that changes during a command', () {
    /// Replaces the stale session `gone` with `fresh`, and runs [change]
    /// while the command reads the tree.
    Future<_Run> runReplacingSession(void Function() change) {
      saveSession(sessionId: 'gone');
      server
        ..on('POST', '/session', {'sessionId': 'fresh', 'capabilities': {}})
        ..on('POST', '/session/fresh/appium/settings', null)
        ..on('GET', '/session/fresh/source', _source)
        ..onRequest = (key) {
          if (key == 'GET /session/fresh/source') change();
        };
      return run(['native-get-elements', '--no-include-foreground-app']);
    }

    test('keeps a newer native-connect with the same session id', () async {
      final reconnected = NativeSessionInfo(
        name: 'default',
        platform: NativePlatform.ios,
        baseUrl: 'http://127.0.0.1:8100',
        createdAt: DateTime.utc(2026, 10, 21),
        udid: 'test-udid',
        sessionId: 'gone',
        startedServer: true,
      );

      final result =
          await runReplacingSession(() => nativeRegistry.save(reconnected));

      expect(result.code, 0, reason: result.err);
      expect(nativeRegistry.get('default')!.toJson(), reconnected.toJson());
    });

    test('keeps the session id another command saved', () async {
      final result =
          await runReplacingSession(() => saveSession(sessionId: 'other'));

      expect(result.code, 0, reason: result.err);
      expect(nativeRegistry.get('default')!.sessionId, 'other');
    });

    test('does not recreate an entry native-disconnect removed', () async {
      final result =
          await runReplacingSession(() => nativeRegistry.remove('default'));

      expect(result.code, 0, reason: result.err);
      expect(nativeRegistry.get('default'), isNull);
    });
  });

  test('a session that cannot be saved does not hide the result', () async {
    saveSession(sessionId: 'gone');
    server
      ..on('POST', '/session', {'sessionId': 'fresh', 'capabilities': {}})
      ..on('POST', '/session/fresh/appium/settings', null)
      ..on('GET', '/session/fresh/source', _source);
    final sessions = '${tempDir.path}/native';
    await Process.run('chmod', ['a-w', sessions]);
    addTearDown(() => Process.run('chmod', ['u+w', sessions]));

    final result = await run(
      ['native-get-elements', '--no-include-foreground-app'],
    );

    expect(result.code, 0, reason: result.err);
    expect(result.out, contains('Allow'));
    expect(result.err, contains('Warning: could not save native session'));
  }, testOn: '!windows');

  test('a session entry broken during a command does not hide the result',
      () async {
    saveSession(sessionId: 'gone');
    server
      ..on('POST', '/session', {'sessionId': 'fresh', 'capabilities': {}})
      ..on('POST', '/session/fresh/appium/settings', null)
      ..on('GET', '/session/fresh/source', _source)
      ..onRequest = (key) {
        if (key == 'GET /session/fresh/source') {
          File('${tempDir.path}/native/default.json').writeAsStringSync('{');
        }
      };

    final result = await run(
      ['native-get-elements', '--no-include-foreground-app'],
    );

    expect(result.code, 0, reason: result.err);
    expect(result.out, contains('Allow'));
    expect(result.err, contains('Warning: could not save native session'));
  });

  test('with --session-dir, a screenshot is kept in the report too', () async {
    saveSession(sessionId: 'kept');
    server
      ..on('GET', '/session/kept/orientation', 'PORTRAIT')
      ..on('GET', '/session/kept/screenshot', _onePixelPng);
    final output = '${tempDir.path}/shot.png';

    final result = await run([
      '--session-dir',
      '${tempDir.path}/reports',
      'native-take-screenshot',
      '-o',
      output,
    ]);

    expect(result.code, 0, reason: result.err);
    expect(File(output).existsSync(), isTrue);
    expect(result.out, contains('Saved a copy in the session: '));
    final sessionDir = Directory('${tempDir.path}/reports/.marionette/sessions')
        .listSync()
        .whereType<Directory>()
        .single;
    expect(
      File('${sessionDir.path}/screenshots/01.png').existsSync(),
      isTrue,
    );
    expect(
      File('${sessionDir.path}/steps.md').readAsStringSync(),
      contains('Saved 1 screenshot(s): screenshots/01.png'),
    );
  });

  test('without the variable or a session flag, writes no report', () async {
    saveSession(sessionId: 'kept');
    server
      ..on('GET', '/session/kept/orientation', 'PORTRAIT')
      ..on('POST', '/session/kept/actions', null);

    final result = await run(['native-tap', '--x', '10', '--y', '20']);

    expect(result.code, 0, reason: result.err);
    expect(Directory('${tempDir.path}/.marionette').existsSync(), isFalse);
  });

  test('logs ok, without the elements, for get-elements and wait-for',
      () async {
    saveSession(sessionId: 'kept');
    server
      ..on('GET', '/session/kept/orientation', 'PORTRAIT')
      ..on('GET', '/session/kept/source', _source);
    final environment = {'MARIONETTE_SESSION_DIR': '${tempDir.path}/reports'};

    for (final args in [
      ['native-get-elements', '--no-include-foreground-app'],
      ['native-wait-for', '--text', 'Allow'],
    ]) {
      final result = await run(args, environment: environment);
      expect(result.code, 0, reason: result.err);
    }

    final steps = Directory('${tempDir.path}/reports/.marionette/sessions')
        .listSync()
        .whereType<Directory>()
        .map((dir) => File('${dir.path}/steps.md').readAsStringSync().trim())
        .toList()
      ..sort();
    expect(steps, hasLength(2));
    expect(steps.first, matches(r'native-get-elements.* -> ok$'));
    expect(steps.last, matches(r'native-wait-for.* -> ok$'));
  });

  test('with only MARIONETTE_SESSION_DIR set, logs the tool message', () async {
    saveSession(sessionId: 'kept');
    server
      ..on('GET', '/session/kept/orientation', 'PORTRAIT')
      ..on('POST', '/session/kept/actions', null);

    final result = await run(
      ['native-tap', '--x', '10', '--y', '20'],
      environment: {'MARIONETTE_SESSION_DIR': '${tempDir.path}/reports'},
    );

    expect(result.code, 0, reason: result.err);
    final sessionDir = Directory('${tempDir.path}/reports/.marionette/sessions')
        .listSync()
        .whereType<Directory>()
        .single;
    expect(
      File('${sessionDir.path}/steps.md').readAsStringSync(),
      contains('native-tap x=10 y=20 -> Successfully tapped at (10, 20)'),
    );
  });

  test('--session-dir wins over MARIONETTE_SESSION_DIR', () async {
    saveSession(sessionId: 'kept');
    server
      ..on('GET', '/session/kept/orientation', 'PORTRAIT')
      ..on('POST', '/session/kept/actions', null);

    final result = await run(
      [
        '--session-dir',
        '${tempDir.path}/explicit',
        'native-tap',
        '--x',
        '10',
        '--y',
        '20',
      ],
      environment: {'MARIONETTE_SESSION_DIR': '${tempDir.path}/from-env'},
    );

    expect(result.code, 0, reason: result.err);
    expect(
      Directory('${tempDir.path}/explicit/.marionette/sessions').existsSync(),
      isTrue,
    );
    expect(Directory('${tempDir.path}/from-env').existsSync(), isFalse);
  });

  test('a tool error exits 1 with the shared message on stderr', () async {
    saveSession(sessionId: 'kept');
    server
      ..on('GET', '/session/kept/orientation', 'PORTRAIT')
      ..on('GET', '/session/kept/source', _source);

    final result = await run(['native-tap', '--text', 'Deny']);

    expect(result.code, 1);
    expect(result.err, contains('No native element with text="Deny"'));
    expect(result.err, contains('Hint:'));
  });

  test('a session lost during a command says to run native-connect', () async {
    saveSession(sessionId: 'kept');
    server.on('GET', '/session/kept/orientation', 'PORTRAIT');

    final result = await run(
      ['native-get-elements', '--no-include-foreground-app'],
    );

    expect(result.code, 1);
    expect(result.err, contains('native session is gone'));
    expect(result.err, contains('Call native-connect again.'));
  });

  test('a server that is gone is reported with a hint', () async {
    saveSession(sessionId: 'kept');
    await server.close();

    final result = await run(['native-get-elements']);

    expect(result.code, 1);
    expect(result.err, contains('is not running'));
    expect(result.err, contains('native-connect'));
  });

  test('a server that never answers /status fails the attach in time',
      () async {
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);
    final connections = <Socket>[];
    silent.listen(connections.add);
    addTearDown(() {
      for (final socket in connections) {
        socket.destroy();
      }
    });
    saveSession(baseUrl: 'http://127.0.0.1:${silent.port}');
    final stopwatch = Stopwatch()..start();

    final result = await run(['native-get-elements']);

    expect(result.code, 1);
    expect(result.err, contains('is not running'));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('tool names in messages become CLI commands; JSON is left alone', () {
    const commands = {'native-get-elements', 'native-tap'};

    expect(
      cliText('Call native_get_elements and native_tap.', commands),
      'Call native-get-elements and native-tap.',
    );
    expect(cliText('{"note":"native_tap"}', commands), '{"note":"native_tap"}');
  });

  test('only names of CLI commands are renamed, not ids', () {
    expect(
      cliText(
        'No field with id="com.example.counter:id/native_form_name". '
        'Call native_connect again.',
        {'native-connect'},
      ),
      'No field with id="com.example.counter:id/native_form_name". '
      'Call native-connect again.',
    );
  });

  test('an id that ends in a command name is left as it is', () {
    expect(
      cliText(
        'No field with id="com.example.counter:id/native_tap".',
        {'native-tap'},
      ),
      'No field with id="com.example.counter:id/native_tap".',
    );
  });

  test('a quoted id or text that holds a command name is left as it is', () {
    expect(
      cliText(
        'No element matches id="native_tap", text="Run native_tap". '
        'Call native_connect again.',
        {'native-tap', 'native-connect'},
      ),
      'No element matches id="native_tap", text="Run native_tap". '
      'Call native-connect again.',
    );
  });

  test('native-sessions lists sessions with their server state', () async {
    saveSession(name: 'pixel');

    final result = await run(['native-sessions']);

    expect(result.code, 0);
    expect(result.out, contains('pixel\tandroid\ttest-serial'));
    expect(result.out, contains('running'));
  });

  test('native-connect refuses to replace a session whose server it started',
      () async {
    saveSession(sessionId: 'kept', startedServer: true);
    final before = nativeRegistry.get('default')!.toJson();

    final result = await run(
      ['native-connect', '--platform', 'android', '--serial', 'other-serial'],
    );

    expect(result.code, 1);
    expect(result.err, contains('native-disconnect'));
    expect(result.err, contains('--native-device'));
    expect(nativeRegistry.get('default')!.toJson(), before);
  });

  test('native-connect to the device of a running session reuses it', () async {
    saveSession(sessionId: 'kept', startedServer: true);
    final before = nativeRegistry.get('default')!.toJson();

    final result = await run(
      ['native-connect', '--platform', 'android', '--serial', 'test-serial'],
    );

    expect(result.code, 0, reason: result.err);
    expect(result.out, contains('is already connected'));
    expect(nativeRegistry.get('default')!.toJson(), before);
    expect(server.requests, ['GET /status']);
  });

  test(
    'native-connect to another device does not refuse a session whose server '
    'it did not start',
    () async {
      saveSession(sessionId: 'kept');

      final result = await run(['native-connect', '--platform', 'ios']);

      expect(result.out, contains('Starting the native server (ios)'));
      expect(result.err, isNot(contains('native-disconnect')));
    },
    // The new bootstrap fails at once only on a host that is not macOS, so
    // nothing is replaced: the test checks only that the refusal was skipped.
    testOn: 'linux',
  );

  test(
    'native-connect stops the server it started when that server no longer '
    'answers, before it starts a new one',
    () async {
      final xcodebuild =
          await Process.start('bash', ['-c', 'exec -a xcodebuild sleep 30']);
      addTearDown(xcodebuild.kill);
      final goneUrl = server.baseUrl;
      await server.close();
      nativeRegistry.save(
        NativeSessionInfo(
          name: 'default',
          platform: NativePlatform.ios,
          baseUrl: goneUrl,
          createdAt: DateTime.utc(2026, 10, 20),
          udid: 'test-udid',
          pid: xcodebuild.pid,
          startedServer: true,
        ),
      );

      await run(['native-connect', '--platform', 'ios']);

      await expectLater(
        xcodebuild.exitCode.timeout(const Duration(seconds: 10)),
        completes,
      );
    },
    // The new bootstrap fails at once only on a host that is not macOS.
    testOn: 'linux',
  );

  test('on a Windows host, native commands fail before touching the session',
      () async {
    saveSession(sessionId: 'kept', startedServer: true);
    final before = nativeRegistry.get('default')!.toJson();

    for (final args in [
      ['native-connect', '--platform', 'android'],
      ['native-disconnect'],
    ]) {
      final result = await run(args, operatingSystem: 'windows');

      expect(result.code, 1, reason: '$args');
      expect(
        result.err,
        contains('The native lane supports macOS and Linux hosts.'),
        reason: '$args',
      );
    }
    expect(nativeRegistry.get('default')!.toJson(), before);
    expect(server.requests, isEmpty);
  });

  group('oneClientWarning', () {
    NativeSessionInfo iosSession({required bool startedServer}) =>
        NativeSessionInfo(
          name: 'default',
          platform: NativePlatform.ios,
          baseUrl: 'http://127.0.0.1:8100',
          createdAt: DateTime.utc(2026, 10, 20),
          udid: 'test-udid',
          startedServer: startedServer,
        );

    test('warns when the server was already running', () {
      expect(oneClientWarning(iosSession(startedServer: false)), isNotNull);
    });

    test('says nothing when this CLI started the server', () {
      expect(oneClientWarning(iosSession(startedServer: true)), isNull);
    });
  });

  test('native-disconnect forgets a session whose server it did not start',
      () async {
    saveSession(sessionId: 'kept');
    server.on('DELETE', '/session/kept', null);

    final result = await run(['native-disconnect']);

    expect(result.code, 0);
    expect(result.out, contains('left running'));
    expect(
      server.requests,
      isNot(contains('DELETE /session/kept')),
      reason: 'deleting it would stop UIAutomator2 of the other process',
    );
    expect(nativeRegistry.get('default'), isNull);
  });
}

typedef _Run = ({int code, String out, String err});

/// Minimal W3C WebDriver server: `/status` is healthy, other routes answer
/// what [on] registered, the rest `invalid session id`.
class _FakeWebDriver {
  _FakeWebDriver._(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakeWebDriver> start() async =>
      _FakeWebDriver._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final _routes = <String, Object?>{
    'GET /status': {'ready': true}
  };
  final requests = <String>[];

  /// Called with `<method> <path>` of each request before it is answered.
  void Function(String key)? onRequest;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  void on(String method, String path, Object? value) =>
      _routes['$method $path'] = value;

  Future<void> _handle(HttpRequest request) async {
    await request.drain<void>();
    final key = '${request.method} ${request.uri.path}';
    requests.add(key);
    onRequest?.call(key);
    final response = request.response..headers.contentType = ContentType.json;
    if (_routes.containsKey(key)) {
      response.write(jsonEncode({'value': _routes[key]}));
    } else {
      response
        ..statusCode = HttpStatus.notFound
        ..write(jsonEncode({
          'value': {'error': 'invalid session id', 'message': 'no session'},
        }));
    }
    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}

class _CapturingStdout implements Stdout {
  final _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
