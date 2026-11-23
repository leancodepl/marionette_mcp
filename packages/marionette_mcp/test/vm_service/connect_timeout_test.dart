import 'dart:async';
import 'dart:io';

import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_context.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'fake_vm_service.dart';

/// Forwards TCP traffic to a VM service until it freezes: then it stops
/// reading from the client, as the VM service of a stopped app process does.
class _FreezableProxy {
  _FreezableProxy._(this._server);

  final ServerSocket _server;
  final _sockets = <Socket>[];
  late StreamSubscription<List<int>> _clientRead;
  var _received = 0;
  int? _freezeAt;
  final _frozen = Completer<void>();

  static Future<_FreezableProxy> start(FakeVmService target) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _FreezableProxy._(server);
    server.listen((client) async {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        target.port,
      );
      proxy._sockets.addAll([client, upstream]);
      upstream.listen(client.add, onDone: client.destroy);
      proxy._clientRead = client.listen(
        (data) {
          upstream.add(data);
          proxy._received += data.length;
          final freezeAt = proxy._freezeAt;
          if (freezeAt != null && proxy._received >= freezeAt) {
            proxy._clientRead.pause();
            proxy._frozen.complete();
          }
        },
        onDone: upstream.destroy,
      );
    });
    return proxy;
  }

  String get uri => 'ws://127.0.0.1:${_server.port}/ws';

  /// Freezes once the client has sent [bytes] more bytes.
  Future<void> freezeAfter(int bytes) {
    _freezeAt = _received + bytes;
    return _frozen.future;
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

void main() {
  late FakeVmService vmService;
  late VmServiceConnector connector;

  setUp(() async {
    vmService = await FakeVmService.start();
    connector = VmServiceConnector();
  });

  tearDown(() async {
    await connector.disconnect();
    await vmService.close();
  });

  /// Connects to [vmService] through a proxy that freezes in the middle of
  /// a large request, so closing the connection can't flush it and finish.
  Future<void> connectToFrozenApp() async {
    final proxy = await _FreezableProxy.start(vmService);
    addTearDown(proxy.close);
    await connector.connect(proxy.uri);
    final frozen = proxy.freezeAfter(1 << 20);
    connector.callCustomExtension('flood', {'data': 'x' * (32 << 20)}).ignore();
    await frozen;
  }

  test('connects to a responsive VM service', () async {
    await connector.connect(vmService.uri);

    expect(connector.isConnected, isTrue);
  });

  test('connects through the http URI that flutter run prints', () async {
    await connector.connect(vmService.httpUri);

    expect(connector.isConnected, isTrue);
  });

  test('times out when the VM service stops answering requests', () async {
    vmService.answerRequests = false;

    final stopwatch = Stopwatch()..start();
    await expectLater(
      connector.connect(
        vmService.uri,
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(
        isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          contains(
              'Timed out connecting to the VM service at ${vmService.uri}'),
        ),
      ),
    );

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(connector.isConnected, isFalse);
  });

  test('times out when the WebSocket handshake never completes', () async {
    vmService.acceptUpgrade = false;

    await expectLater(
      connector.connect(
        vmService.uri,
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(connector.isConnected, isFalse);
  });

  test('can connect again after a timed-out attempt', () async {
    vmService.answerRequests = false;
    await expectLater(
      connector.connect(
        vmService.uri,
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );

    vmService.answerRequests = true;
    await connector.connect(vmService.uri);

    expect(connector.isConnected, isTrue);
  });

  test('a timed-out attempt closes its connection and leaves the next alone',
      () async {
    vmService.answerRequests = false;
    final other = await FakeVmService.start();
    addTearDown(other.close);

    final timedOut = expectLater(
      connector.connect(vmService.uri, timeout: const Duration(seconds: 3)),
      throwsA(isA<TimeoutException>()),
    );
    await vmService.requests.stream.firstWhere((method) => method == 'getVM');
    await connector.connect(other.uri);
    final pending = connector.waitForServiceRegistration(
      'reloadSources',
      timeout: const Duration(milliseconds: 500),
    );
    vmService.registerService('reloadSources', 's_stale.reloadSources');
    expect(await pending, isNull);
    await timedOut;

    expect(
      await connector.waitForServiceRegistration(
        'reloadSources',
        timeout: const Duration(milliseconds: 100),
      ),
      isNull,
    );
    await vmService.sockets.single.done.timeout(const Duration(seconds: 2));
    expect(connector.isConnected, isTrue);
  });

  test('an attempt overtaken by a newer connect closes itself', () async {
    vmService.hold = Completer<void>();
    final other = await FakeVmService.start();
    addTearDown(other.close);

    final overtaken = expectLater(
      connector.connect(vmService.uri),
      throwsA(isA<StateError>()),
    );
    await vmService.requests.stream.firstWhere((method) => method == 'getVM');
    await connector.connect(other.uri);
    vmService.hold!.complete();
    await overtaken;

    await vmService.sockets.single.done.timeout(const Duration(seconds: 2));
    expect(connector.isConnected, isTrue);
  });

  test('gives up at its deadline even when the previous app froze', () async {
    await connectToFrozenApp();
    final silent = await FakeVmService.start();
    addTearDown(silent.close);
    silent.answerRequests = false;

    final stopwatch = Stopwatch()..start();
    await expectLater(
      connector.connect(
        silent.uri,
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('connect tool gives up when the app does not answer extensions',
      () async {
    vmService.answerExtensions = false;
    final context = VmServiceContext(
      connectTimeout: const Duration(seconds: 1),
    );
    final client = await startTools(context);

    final stopwatch = Stopwatch()..start();
    final result = await callConnect(client, vmService.uri)
        .timeout(const Duration(seconds: 5));

    expect(result.isError, isTrue);
    expect(
      (result.content.single as TextContent).text,
      contains('is not paused in the debugger'),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(context.connector.isConnected, isFalse);
  });

  test('a replaced connect call leaves the newer connection alone', () async {
    vmService.answerExtensions = false;
    final other = await FakeVmService.start();
    addTearDown(other.close);
    final client = await startTools(VmServiceContext());

    final replaced = callConnect(client, vmService.uri);
    await vmService.requests.stream
        .firstWhere((method) => method == 'ext.flutter.marionette.getVersion');
    final newer = await callConnect(client, other.uri);

    expect(newer.isError, isFalse);
    expect((await replaced).isError, isTrue);
  });

  test('a timed-out connect call does not log into a newer session', () async {
    vmService.answerRequests = false;
    final other = await FakeVmService.start();
    addTearDown(other.close);
    final sessions = await Directory.systemTemp.createTemp('marionette_test');
    addTearDown(() => sessions.delete(recursive: true));
    final client = await startTools(
      VmServiceContext(connectTimeout: const Duration(seconds: 3)),
    );

    final timedOut = callConnect(client, vmService.uri);
    await vmService.requests.stream.firstWhere((method) => method == 'getVM');
    final newer =
        await callConnect(client, other.uri, sessionDir: sessions.path);
    expect(newer.isError, isFalse);
    expect((await timedOut).isError, isTrue);

    final steps = sessions
        .listSync(recursive: true)
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('steps.md'))
        .readAsStringSync();
    expect(steps, contains('127.0.0.1:${other.port}'));
    expect(steps, isNot(contains('127.0.0.1:${vmService.port}')));
  });

  test('still reports a missing marionette binding without waiting', () async {
    vmService.extensionRPCs = [];

    await expectLater(
      connector.connect(vmService.uri),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No isolate found'),
        ),
      ),
    );

    expect(connector.isConnected, isFalse);
  });

  test('stops waiting for a frozen VM service to close after 5 s', () async {
    await connectToFrozenApp();

    final stopwatch = Stopwatch()..start();
    await connector.disconnect().timeout(const Duration(seconds: 10));

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 7)));
    expect(connector.isConnected, isFalse);
  });
}
