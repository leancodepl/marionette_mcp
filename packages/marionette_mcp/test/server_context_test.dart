import 'dart:async';
import 'dart:io';

import 'package:marionette_mcp/marionette_mcp.dart';
import 'package:marionette_mcp/runtime.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  test('an older disconnect preserves a replacement connection session',
      () async {
    final directory =
        Directory.systemTemp.createTempSync('marionette-overlap-');
    final connector = _DelayedDisconnectConnector();
    final context = VmServiceContext(connector: connector);
    final server = _CapturingServer();
    context.registerTools(server);
    addTearDown(() async {
      if (!connector.release.isCompleted) connector.release.complete();
      await context.dispose();
      await server.close();
      directory.deleteSync(recursive: true);
    });
    final extra = _UnusedExtra();
    Future<CallToolResult> call(String name, Map<String, dynamic> args) async =>
        server.callbacks[name]!(args, extra);
    Map<String, dynamic> connectArgs(String title) => {
          'uri': 'ws://fixture/ws',
          'session_title': title,
          'session_dir': directory.path,
        };
    expect((await call('connect', connectArgs('first'))).isError, isFalse);

    connector.holdOnce = true;
    final disconnect = call('disconnect', {});
    await connector.started.future;
    expect(
        (await call('connect', connectArgs('replacement'))).isError, isFalse);
    expect(
        (await call('take_screenshots', {'inline': false})).isError, isFalse);

    connector.release.complete();
    expect((await disconnect).isError, isFalse);
    expect(
        (await call('take_screenshots', {'inline': false})).isError, isFalse);

    final sessions = Directory('${directory.path}/.marionette/sessions')
        .listSync()
        .whereType<Directory>()
        .toList();
    final first = sessions.singleWhere((entry) => entry.path.contains('first'));
    final replacement =
        sessions.singleWhere((entry) => entry.path.contains('replacement'));
    expect(File('${first.path}/steps.md').readAsStringSync(),
        contains('disconnect'));
    expect(File('${replacement.path}/steps.md').readAsStringSync(),
        isNot(contains('disconnect')));
  });
}

class _CapturingServer extends McpServer {
  _CapturingServer()
      : super(const Implementation(name: 'context-test', version: '1'));

  final callbacks = <String, ToolFunction>{};

  @override
  RegisteredTool registerTool(
    String name, {
    String? title,
    String? description,
    ToolInputSchema? inputSchema,
    ToolOutputSchema? outputSchema,
    ToolAnnotations? annotations,
    Map<String, dynamic>? meta,
    required ToolFunction callback,
  }) {
    callbacks[name] = callback;
    return super.registerTool(
      name,
      title: title,
      description: description,
      inputSchema: inputSchema,
      outputSchema: outputSchema,
      annotations: annotations,
      meta: meta,
      callback: callback,
    );
  }
}

class _UnusedExtra implements RequestHandlerExtra {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _DelayedDisconnectConnector extends VmServiceConnector {
  bool holdOnce = false;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> connect(String uri) async {}

  @override
  Future<void> disconnect() async {
    if (holdOnce) {
      holdOnce = false;
      started.complete();
      await release.future;
    }
  }

  @override
  Future<String> getVersion() async => version;

  @override
  Future<bool> getSessionReportsEnabled() async => true;

  @override
  Future<Map<String, dynamic>> listExtensions() async => {'extensions': []};

  @override
  Future<Map<String, dynamic>> takeScreenshots() async => {
        'screenshots': ['aGVsbG8='],
      };
}
