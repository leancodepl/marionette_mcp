import 'dart:convert';
import 'dart:io';

import 'package:marionette_cli/src/cli/marionette_command_runner.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:test/test.dart';

const _source = '<hierarchy>'
    '<node class="android.widget.Button" text="Allow" clickable="true" '
    'bounds="[0,0][100,50]"/>'
    '</hierarchy>';

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

  void saveSession({String? sessionId, String name = 'default'}) =>
      nativeRegistry.save(
        NativeSessionInfo(
          name: name,
          platform: 'android',
          baseUrl: server.baseUrl,
          createdAt: DateTime.utc(2026, 10, 20),
          serial: 'test-serial',
          sessionId: sessionId,
        ),
      );

  Future<_Run> run(List<String> args) async {
    final out = _CapturingStdout();
    final err = _CapturingStdout();
    final code = await IOOverrides.runZoned(
      () => MarionetteCommandRunner(
        registry: InstanceRegistry(baseDir: '${tempDir.path}/instances'),
        nativeRegistry: nativeRegistry,
      ).run(args),
      stdout: () => out,
      stderr: () => err,
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
      ['--native-session', 'pixel', 'native-tap', '--text', 'Allow'],
    );

    expect(result.err, contains('--native-session pixel native-connect'));
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

  test('a server that is gone is reported with a hint', () async {
    saveSession(sessionId: 'kept');
    await server.close();

    final result = await run(['native-get-elements']);

    expect(result.code, 1);
    expect(result.err, contains('is not running'));
    expect(result.err, contains('native-connect'));
  });

  test('tool names in messages become CLI commands; JSON is left alone', () {
    expect(
      cliText('Call native_get_elements and native_tap.'),
      'Call native-get-elements and native-tap.',
    );
    expect(cliText('{"note":"native_tap"}'), '{"note":"native_tap"}');
  });

  test('native-sessions lists sessions with their server state', () async {
    saveSession(name: 'pixel');

    final result = await run(['native-sessions']);

    expect(result.code, 0);
    expect(result.out, contains('pixel\tandroid\ttest-serial'));
    expect(result.out, contains('running'));
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

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  void on(String method, String path, Object? value) =>
      _routes['$method $path'] = value;

  Future<void> _handle(HttpRequest request) async {
    await request.drain<void>();
    final key = '${request.method} ${request.uri.path}';
    requests.add(key);
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
