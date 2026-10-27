import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

/// A local stand-in for an app's VM service whose replies the test controls.
class _FakeVmService {
  _FakeVmService._(this._server);

  final HttpServer _server;
  final _sockets = <WebSocket>[];

  /// Whether the server completes the WebSocket upgrade at all.
  bool acceptUpgrade = true;

  /// Whether the server answers JSON-RPC requests once connected.
  bool answerRequests = true;

  /// Extensions the single fake isolate reports.
  List<String> extensionRPCs = ['ext.flutter.marionette.getLogs'];

  /// The method of every request the server receives.
  final requests = StreamController<String>.broadcast();

  static Future<_FakeVmService> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeVmService._(server);
    server.listen(fake._handle);
    return fake;
  }

  String get uri => 'ws://127.0.0.1:${_server.port}/ws';

  Future<void> _handle(HttpRequest request) async {
    // Leaving the request open simulates a VM service that accepted the
    // TCP connection but never finishes the handshake.
    if (!acceptUpgrade) return;
    // Uncompressed, so a large request fills the socket buffers.
    final socket = await WebSocketTransformer.upgrade(
      request,
      compression: CompressionOptions.compressionOff,
    );
    _sockets.add(socket);
    socket.listen((data) {
      final request = jsonDecode(data as String) as Map<String, dynamic>;
      requests.add(request['method'] as String);
      if (!answerRequests) return;
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': request['id'],
        'result': _result(request['method'] as String),
      }));
    });
  }

  Map<String, dynamic> _result(String method) {
    const isolateRef = {
      'type': '@Isolate',
      'id': 'isolates/1',
      'number': '1',
      'name': 'main',
      'isSystemIsolate': false,
    };
    return switch (method) {
      'getVM' => {
          'type': 'VM',
          'name': 'vm',
          'architectureBits': 64,
          'hostCPU': '',
          'operatingSystem': '',
          'targetCPU': '',
          'version': '',
          'pid': 1,
          'startTime': 0,
          'isolates': [isolateRef],
          'isolateGroups': <Object>[],
          'systemIsolates': <Object>[],
          'systemIsolateGroups': <Object>[],
        },
      'getIsolate' => {
          ...isolateRef,
          'type': 'Isolate',
          'isolateFlags': <Object>[],
          'startTime': 0,
          'runnable': true,
          'livePorts': 0,
          'pauseOnExit': false,
          'pauseEvent': {'type': 'Event', 'kind': 'Resume', 'timestamp': 0},
          'libraries': <Object>[],
          'breakpoints': <Object>[],
          'exceptionPauseMode': 'None',
          'extensionRPCs': extensionRPCs,
        },
      _ => {'type': 'Success'},
    };
  }

  /// Announces a service registration, as Flutter tools do over DDS.
  void registerService(String service, String method) {
    _sockets.single.add(jsonEncode({
      'jsonrpc': '2.0',
      'method': 'streamNotify',
      'params': {
        'streamId': 'Service',
        'event': {
          'type': 'Event',
          'kind': 'ServiceRegistered',
          'service': service,
          'method': method,
          'alias': 'Flutter Tools',
          'timestamp': 0,
        },
      },
    }));
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}

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

  static Future<_FreezableProxy> start(_FakeVmService target) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _FreezableProxy._(server);
    server.listen((client) async {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        target._server.port,
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
  late _FakeVmService vmService;
  late VmServiceConnector connector;

  setUp(() async {
    vmService = await _FakeVmService.start();
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
    final other = await _FakeVmService.start();
    addTearDown(other.close);

    final timedOut = expectLater(
      connector.connect(vmService.uri, timeout: const Duration(seconds: 1)),
      throwsA(isA<TimeoutException>()),
    );
    await vmService.requests.stream.firstWhere((method) => method == 'getVM');
    await connector.connect(other.uri);
    vmService.registerService('reloadSources', 's_stale.reloadSources');
    await timedOut;

    expect(
      await connector.waitForServiceRegistration(
        'reloadSources',
        timeout: const Duration(milliseconds: 100),
      ),
      isNull,
    );
    await vmService._sockets.single.done.timeout(const Duration(seconds: 2));
    expect(connector.isConnected, isTrue);
  });

  test('gives up at its deadline even when the previous app froze', () async {
    await connectToFrozenApp();
    final silent = await _FakeVmService.start();
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
