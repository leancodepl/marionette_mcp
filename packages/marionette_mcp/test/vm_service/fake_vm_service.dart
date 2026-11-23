import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/version.g.dart' as v;
import 'package:marionette_mcp/src/vm_service/vm_service_context.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

/// A local stand-in for an app's VM service whose replies the test controls.
class FakeVmService {
  FakeVmService._(this._server);

  final HttpServer _server;

  /// The WebSockets clients opened, in order.
  final sockets = <WebSocket>[];

  /// Whether the server completes the WebSocket upgrade at all.
  bool acceptUpgrade = true;

  /// Whether the server answers JSON-RPC requests once connected.
  bool answerRequests = true;

  /// Whether the app answers service extension calls, which it doesn't
  /// while it is paused in the debugger.
  bool answerExtensions = true;

  /// Extensions the single fake isolate reports.
  List<String> extensionRPCs = [
    'ext.flutter.marionette.getLogs',
    'ext.flutter.marionette.getConfiguration',
  ];

  /// The id of the single fake isolate; a hot restart replaces it.
  String isolateId = 'isolates/1';

  /// The URIs of the libraries the isolate reports; null leaves the field
  /// out, as a VM service without library metadata does.
  List<String>? libraryUris = [];

  /// The body of the `marionette.getConfiguration` reply.
  Map<String, dynamic> configuration = {
    'enableSessionReports': true,
    'uiLibraries': <String>[],
  };

  /// When set, `getIsolate` fails with this JSON-RPC error message.
  String? getIsolateError;

  /// The body of the `marionette.interactiveElements` reply.
  Map<String, dynamic> interactiveElements = {'elements': <Object>[]};

  /// When set, replies wait until it completes.
  Completer<void>? hold;

  /// When set, [hold] delays only the replies to this method.
  String? heldMethod;

  /// The method of every request the server receives.
  final requests = StreamController<String>.broadcast();

  /// The method of every request the server received so far.
  final receivedMethods = <String>[];

  static Future<FakeVmService> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeVmService._(server);
    server.listen(fake._handle);
    return fake;
  }

  int get port => _server.port;

  String get uri => 'ws://127.0.0.1:$port/ws';

  /// The form `flutter run` prints.
  String get httpUri => 'http://127.0.0.1:$port/AbC=/';

  Future<void> _handle(HttpRequest request) async {
    // Leaving the request open simulates a VM service that accepted the
    // TCP connection but never finishes the handshake.
    if (!acceptUpgrade) return;
    // Uncompressed, so a large request fills the socket buffers.
    final socket = await WebSocketTransformer.upgrade(
      request,
      compression: CompressionOptions.compressionOff,
    );
    sockets.add(socket);
    socket.listen((data) async {
      final request = jsonDecode(data as String) as Map<String, dynamic>;
      final method = request['method'] as String;
      receivedMethods.add(method);
      requests.add(method);
      if (!answerRequests) return;
      if (!answerExtensions && method.startsWith('ext.')) return;
      if (heldMethod == null || heldMethod == method) await hold?.future;
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'id': request['id'],
        ..._reply(method),
      }));
    });
  }

  Map<String, dynamic> _reply(String method) {
    if (method == 'getIsolate' && getIsolateError != null) {
      return {
        'error': {'code': -32000, 'message': getIsolateError},
      };
    }
    return {'result': _result(method)};
  }

  Map<String, dynamic> _result(String method) {
    final isolateRef = {
      'type': '@Isolate',
      'id': isolateId,
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
          if (libraryUris case final uris?)
            'libraries': [
              for (final (index, uri) in uris.indexed)
                {
                  'type': '@Library',
                  'id': 'libraries/$index',
                  'name': '',
                  'uri': uri,
                },
            ],
          'breakpoints': <Object>[],
          'exceptionPauseMode': 'None',
          'extensionRPCs': extensionRPCs,
        },
      'ext.flutter.marionette.getVersion' => {
          'type': '_ext',
          'version': v.version,
        },
      'ext.flutter.marionette.getConfiguration' => {
          'type': '_ext',
          ...configuration,
        },
      'ext.flutter.marionette.listExtensions' => {
          'type': '_ext',
          'extensions': <Object>[],
        },
      'ext.flutter.marionette.interactiveElements' => {
          'type': '_ext',
          ...interactiveElements,
        },
      _ => {'type': 'Success'},
    };
  }

  /// Announces a service registration, as Flutter tools do over DDS.
  void registerService(String service, String method) {
    sockets.last.add(jsonEncode({
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
    for (final socket in sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}

/// Serves [context]'s tools to an in-process MCP client.
Future<McpClient> startTools(VmServiceContext context) async {
  final server = McpServer(
    const Implementation(name: 'test-server', version: '0.0.0'),
    options: const McpServerOptions(
      capabilities: ServerCapabilities(
        tools: ServerCapabilitiesTools(listChanged: true),
      ),
    ),
  );
  context.registerTools(server, enableNativeLane: false);
  final toServer = StreamController<List<int>>();
  final toClient = StreamController<List<int>>();
  await server.connect(
    IOStreamTransport(stream: toServer.stream, sink: toClient.sink),
  );
  final client = McpClient(
    const Implementation(name: 'test-client', version: '0.0.0'),
  );
  await client.connect(
    IOStreamTransport(stream: toClient.stream, sink: toServer.sink),
  );
  addTearDown(() async {
    await client.close();
    await server.close();
    await context.connector.disconnect();
  });
  return client;
}

Future<CallToolResult> callConnect(
  McpClient client,
  String uri, {
  String? sessionDir,
}) =>
    client.callTool(
      CallToolRequest(
        name: 'connect',
        arguments: {
          'uri': uri,
          if (sessionDir != null) 'session_dir': sessionDir,
        },
      ),
    );
