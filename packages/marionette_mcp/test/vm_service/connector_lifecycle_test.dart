import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

/// A loopback VM service whose HTTP upgrade or RPC responses can be withheld.
class _VmServer {
  _VmServer(this.server, this.name);

  final HttpServer server;
  final String name;
  final accepted = Completer<HttpRequest>();
  final requests = <Map<String, dynamic>>[];
  final sockets = <WebSocket>[];
  final _requests =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  bool holdUpgrade = false;
  bool holdGetVm = false;
  bool holdGetIsolate = false;
  bool holdGetVersion = false;
  bool respondToStreamListen = true;
  bool registerHotRestart = false;
  String isolateId = 'isolates/1';
  int emptyVmResponses = 0;

  String get uri => 'ws://127.0.0.1:${server.port}/ws';

  static Future<_VmServer> start(String name) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final vm = _VmServer(server, name);
    server.listen(vm._accept);
    return vm;
  }

  Future<void> _accept(HttpRequest request) async {
    if (!accepted.isCompleted) accepted.complete(request);
    if (holdUpgrade) return;
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      requests.add(message);
      _requests.add(message);
      final method = message['method'];
      if ((method == 'streamListen' && !respondToStreamListen) ||
          (method == 'getVM' && holdGetVm) ||
          (method == 'getIsolate' && holdGetIsolate) ||
          (method == 'ext.flutter.marionette.getVersion' && holdGetVersion)) {
        return;
      }
      Map<String, dynamic> result;
      switch (method) {
        case 'getVM':
          final empty = emptyVmResponses > 0;
          if (empty) emptyVmResponses--;
          result = {
            'type': 'VM',
            'isolates': [
              if (!empty)
                {
                  'type': '@Isolate',
                  'id': isolateId,
                  'name': 'main',
                  'number': '1',
                },
            ],
          };
        case 'getIsolate':
          result = {
            'type': 'Isolate',
            'id': isolateId,
            'name': 'main',
            'number': '1',
            'extensionRPCs': ['ext.flutter.marionette.getLogs'],
          };
        case 'ext.flutter.marionette.getVersion':
          result = {'version': name};
        case 's0.hotRestart':
          isolateId = 'isolates/2';
          result = {'type': 'Success'};
        default:
          result = {'type': 'Success'};
      }
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': message['id'],
        'result': result,
      }));
      if (method == 'streamListen' && registerHotRestart) {
        socket.add(jsonEncode({
          'jsonrpc': '2.0',
          'method': 'streamNotify',
          'params': {
            'streamId': 'Service',
            'event': {
              'type': 'Event',
              'kind': 'ServiceRegistered',
              'service': 'hotRestart',
              'method': 's0.hotRestart',
            },
          },
        }));
      }
    });
  }

  Future<void> seen(String method) async {
    if (requests.any((request) => request['method'] == method)) return;
    await _requests.stream
        .firstWhere((request) => request['method'] == method)
        .timeout(const Duration(seconds: 3));
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
    await _requests.close();
  }
}

/// Observe cancellation immediately so a rejected connect cannot go unhandled.
Future<Object?> _failureOf(Future<void> future) => future.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );

void main() {
  group('VM service connection ownership', () {
    late VmServiceConnector connector;
    late List<_VmServer> servers;

    setUp(() {
      connector = VmServiceConnector();
      servers = [];
    });

    tearDown(() async {
      await connector.disconnect();
      for (final server in servers) {
        await server.close();
      }
    });

    Future<_VmServer> server(String name) async {
      final value = await _VmServer.start(name);
      servers.add(value);
      return value;
    }

    test('disconnect aborts an HTTP upgrade that never responds', () async {
      final vm = await server('pending');
      vm.holdUpgrade = true;
      final failure = _failureOf(connector.connect(vm.uri));
      await vm.accepted.future.timeout(const Duration(seconds: 3));

      await connector.disconnect().timeout(const Duration(seconds: 2));

      // The server deliberately never releases the upgrade. Closing only an
      // already-created VmService cannot make this future complete.
      expect(await failure.timeout(const Duration(seconds: 2)), isNotNull);
      expect(connector.isConnected, isFalse);
      expect(vm.sockets, isEmpty);
      await expectLater(
          connector.getVersion(), throwsA(isA<NotConnectedException>()));
    });

    test('same-turn disconnect supersedes connect before socket acquisition',
        () async {
      final vm = await server('cancelled');
      final failure = _failureOf(connector.connect(vm.uri));

      await connector.disconnect();

      expect(
          await failure.timeout(const Duration(seconds: 2)), isA<StateError>());
      expect(connector.isConnected, isFalse);
      expect(vm.accepted.isCompleted, isFalse);
    });

    test('the last of same-turn connect calls owns the connection', () async {
      final old = await server('old');
      final replacement = await server('replacement');
      final oldFailure = _failureOf(connector.connect(old.uri));

      await connector
          .connect(replacement.uri)
          .timeout(const Duration(seconds: 3));

      expect(await oldFailure.timeout(const Duration(seconds: 2)),
          isA<StateError>());
      expect(old.accepted.isCompleted, isFalse);
      expect(await connector.getVersion(), 'replacement');
    });

    test('a replacement connect cancels the previous pending upgrade',
        () async {
      final old = await server('old');
      old.holdUpgrade = true;
      final oldFailure = _failureOf(connector.connect(old.uri));
      await old.accepted.future.timeout(const Duration(seconds: 3));
      final replacement = await server('replacement');

      await connector
          .connect(replacement.uri)
          .timeout(const Duration(seconds: 3));

      expect(await oldFailure.timeout(const Duration(seconds: 2)), isNotNull);
      expect(connector.isConnected, isTrue);
      expect(await connector.getVersion(), 'replacement');
      expect(old.sockets, isEmpty);
    });

    test('stale discovery failure does not disconnect a newer connection',
        () async {
      final old = await server('old');
      old.holdGetVm = true;
      final oldFailure = _failureOf(connector.connect(old.uri));
      await old.seen('getVM');
      final replacement = await server('replacement');

      await connector
          .connect(replacement.uri)
          .timeout(const Duration(seconds: 3));

      expect(await oldFailure.timeout(const Duration(seconds: 2)), isNotNull);
      expect(connector.isConnected, isTrue);
      expect(await connector.getVersion(), 'replacement');
      expect(old.requests.where((r) => r['method'] == 'getIsolate'), isEmpty);
    });

    test('disconnect also cancels pending isolate discovery', () async {
      final vm = await server('discovery');
      vm.holdGetIsolate = true;
      final failure = _failureOf(connector.connect(vm.uri));
      await vm.seen('getIsolate');

      await connector.disconnect().timeout(const Duration(seconds: 2));

      expect(await failure.timeout(const Duration(seconds: 2)), isNotNull);
      expect(connector.isConnected, isFalse);
    });

    test('peer close rejects pending discovery and permits reconnect',
        () async {
      final old = await server('old');
      old.holdGetIsolate = true;
      final failure = _failureOf(connector.connect(old.uri));
      await old.seen('getIsolate');

      await old.sockets.single.close();

      expect(await failure.timeout(const Duration(seconds: 2)), isNotNull);
      expect(connector.isConnected, isFalse);
      final replacement = await server('replacement');
      await connector.connect(replacement.uri);
      expect(await connector.getVersion(), 'replacement');
    });

    test('peer close rejects an established connection RPC without hanging',
        () async {
      final vm = await server('closed-peer');
      await connector.connect(vm.uri);
      vm.holdGetVersion = true;
      final failure = _failureOf(connector.getVersion().then((_) {}));
      await vm.seen('ext.flutter.marionette.getVersion');

      await vm.sockets.single.close();

      expect(await failure.timeout(const Duration(seconds: 2)),
          isA<VmServiceExtensionException>());
      expect(connector.isConnected, isFalse);
      await expectLater(
          connector.getVersion(), throwsA(isA<NotConnectedException>()));
      await connector.disconnect().timeout(const Duration(seconds: 2));
    });

    test('peer close retires service registrations and pending waiters',
        () async {
      final vm = await server('closed-peer');
      vm.registerHotRestart = true;
      await connector.connect(vm.uri);
      expect(await connector.waitForServiceRegistration('hotRestart'),
          's0.hotRestart');
      final waiting = connector.waitForServiceRegistration(
        'pending',
        timeout: const Duration(minutes: 1),
      );

      await vm.sockets.single.close();

      expect(await waiting.timeout(const Duration(seconds: 2)), isNull);
      expect(connector.isConnected, isFalse);
      expect(
        await connector.waitForServiceRegistration(
          'hotRestart',
          timeout: Duration.zero,
        ),
        isNull,
      );
      await expectLater(
          connector.getVersion(), throwsA(isA<NotConnectedException>()));
    });

    test('old peer closure preserves replacement registration waiters',
        () async {
      final old = await server('old');
      await connector.connect(old.uri);
      final replacement = await server('replacement');
      replacement.registerHotRestart = true;

      final connecting = connector.connect(replacement.uri);
      final registration = connector.waitForServiceRegistration(
        'hotRestart',
        timeout: const Duration(seconds: 3),
      );
      await connecting.timeout(const Duration(seconds: 3));

      expect(await registration, 's0.hotRestart');
      expect(connector.isConnected, isTrue);
      expect(await connector.getVersion(), 'replacement');
    });

    test('old disconnect cleanup cannot clear an immediate new connect',
        () async {
      final old = await server('old');
      await connector.connect(old.uri);
      final replacement = await server('replacement');

      final disconnect = connector.disconnect();
      final connect = connector.connect(replacement.uri);
      await Future.wait([disconnect, connect])
          .timeout(const Duration(seconds: 3));

      expect(connector.isConnected, isTrue);
      expect(await connector.getVersion(), 'replacement');
    });

    test('service discovery still proceeds without a streamListen response',
        () async {
      final vm = await server('no-stream-ack');
      vm.respondToStreamListen = false;

      await connector.connect(vm.uri).timeout(const Duration(seconds: 2));

      expect(connector.isConnected, isTrue);
      expect(await connector.getVersion(), 'no-stream-ack');
    });

    test('hot restart still discovers the replacement isolate after retries',
        () async {
      final vm = await server('restart');
      vm.registerHotRestart = true;
      await connector.connect(vm.uri);
      vm.emptyVmResponses = 1;

      expect(await connector.hotRestart().timeout(const Duration(seconds: 3)),
          isTrue);
      expect(await connector.getVersion(), 'restart');
      final version = vm.requests
          .lastWhere((r) => r['method'] == 'ext.flutter.marionette.getVersion');
      expect((version['params'] as Map)['isolateId'], 'isolates/2');
    });

    test('superseded hot restart cannot overwrite a new connection isolate',
        () async {
      final old = await server('old');
      old.registerHotRestart = true;
      await connector.connect(old.uri);
      old.holdGetVm = true;
      final restartFailure = _failureOf(connector.hotRestart().then((_) {}));
      await old.seen('s0.hotRestart');
      final replacement = await server('replacement');
      replacement.isolateId = 'isolates/new';

      await connector
          .connect(replacement.uri)
          .timeout(const Duration(seconds: 3));

      expect(
          await restartFailure.timeout(const Duration(seconds: 2)), isNotNull);
      expect(await connector.getVersion(), 'replacement');
      final version = replacement.requests
          .lastWhere((r) => r['method'] == 'ext.flutter.marionette.getVersion');
      expect((version['params'] as Map)['isolateId'], 'isolates/new');
    });

    test('superseded hot reload does not send an RPC to the replacement',
        () async {
      final old = await server('old');
      await connector.connect(old.uri);
      final reloadFailure = _failureOf(connector.hotReload().then((_) {}));
      final replacement = await server('replacement');

      await connector
          .connect(replacement.uri)
          .timeout(const Duration(seconds: 3));

      expect(
          await reloadFailure.timeout(const Duration(seconds: 2)), isNotNull);
      expect(await connector.getVersion(), 'replacement');
      expect(replacement.requests.where((r) => r['method'] == 'reloadSources'),
          isEmpty);
    });
  });
}
