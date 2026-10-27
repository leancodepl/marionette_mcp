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
    final socket = await WebSocketTransformer.upgrade(request);
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

  test('reconnects when the previous VM service stopped answering', () async {
    await connector.connect(vmService.uri);
    vmService.answerRequests = false;

    final other = await _FakeVmService.start();
    addTearDown(other.close);

    final stopwatch = Stopwatch()..start();
    await connector.connect(other.uri);

    expect(connector.isConnected, isTrue);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
