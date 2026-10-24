import 'dart:async';
import 'dart:io';

import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/vm_service/app_connection_service.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late _Connector connector;
  late AppConnectionService service;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('app-connection-');
    connector = _Connector();
    service = AppConnectionService(
      connector: connector,
      expectedVersion: 'fixture',
    );
  });
  tearDown(() async {
    await service.dispose();
    directory.deleteSync(recursive: true);
  });
  Future<AppConnectionResult> connect([String title = 'run']) =>
      service.connect(
        uri: 'ws://$title/ws',
        sessionTitle: title,
        sessionDir: directory.path,
      );

  test('mismatch disconnects before reporting the actual binding version',
      () async {
    connector.version = () async => 'other';
    final result = await connect();
    expect(result.failure?.kind, AppConnectionFailureKind.versionMismatch);
    expect(result.failure?.actualVersion, 'other');
    expect(connector.disconnects, 1);
    expect(connector.configurationReads, 0);
    expect(directory.listSync(), isEmpty);
  });

  test('failed version check disconnects and retains the original cause',
      () async {
    final error = StateError('missing binding');
    connector.version = () async => throw error;
    final result = await connect();
    expect(result.failure?.kind, AppConnectionFailureKind.versionCheck);
    expect(result.failure?.cause, same(error));
    expect(connector.disconnects, 1);
  });

  test('report opt-out and unreadable configuration create no files', () async {
    connector.reports = () async => false;
    expect((await connect()).session, isNull);
    connector.reports = () async => throw StateError('unsupported');
    final result = await connect();
    expect(result.failure, isNull);
    expect(result.reportWarning, isNull);
    expect(result.session, isNull);
    expect(directory.listSync(), isEmpty);
    expect(connector.disconnects, 0);
  });

  test('report creation failure keeps the app connected with a warning',
      () async {
    final file = File('${directory.path}/file')..writeAsStringSync('fixture');
    final result = await service.connect(
      uri: 'ws://fixture/ws',
      sessionDir: file.path,
    );
    expect(result.failure, isNull);
    expect(result.reportWarning, isA<FileSystemException>());
    expect(result.session, isNull);
    expect(service.session, isNull);
    expect(connector.disconnects, 0);
  });

  test('callbacks retire first and expose only the replacement report',
      () async {
    final events = <String>[];
    final sessions = <Session?>[];
    service = AppConnectionService(
      connector: connector,
      expectedVersion: 'fixture',
      onRetired: () => events.add('retired'),
      onConnected: () async => events.add('connected'),
      onSessionChanged: (session) {
        sessions.add(session);
        events.add(session == null ? 'clear' : 'session');
      },
    );
    final first = await connect('first');
    final second = await connect('second');
    expect(events, [
      'clear',
      'retired',
      'connected',
      'session',
      'clear',
      'retired',
      'connected',
      'session'
    ]);
    expect(sessions, [null, first.session, null, second.session]);
    expect(
        first.session?.directory.path, isNot(second.session?.directory.path));
    expect(service.session, same(second.session));
    expect(service.ownsConnection(first.generation), isFalse);
    expect(service.ownsConnection(second.generation), isTrue);
  });

  test('a failed replacement connect immediately retires the old report',
      () async {
    await connect('first');
    connector.connectError = StateError('offline');
    final pending = connect('replacement');
    expect(service.session, isNull);
    expect((await pending).failure?.kind, AppConnectionFailureKind.connection);
  });

  test('superseded handshake cannot disconnect or replace the current session',
      () async {
    final started = Completer<void>();
    final release = Completer<String>();
    connector.version = () {
      connector.version = () async => 'fixture';
      started.complete();
      return release.future;
    };
    final old = connect('old');
    await started.future;
    final replacement = await connect('replacement');
    release.complete('other');
    final stale = await old;
    expect(stale.failure?.kind, AppConnectionFailureKind.versionCheck);
    expect(service.ownsConnection(stale.generation), isFalse);
    expect(service.session, same(replacement.session));
    expect(connector.disconnects, 0);
  });

  for (final phase in ['discovery', 'configuration']) {
    test('a connect superseded during $phase cannot create a report', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var first = true;
      Future<void> holdFirst() async {
        if (!first) return;
        first = false;
        started.complete();
        await release.future;
      }

      service = AppConnectionService(
        connector: connector,
        expectedVersion: 'fixture',
        onConnected: phase == 'discovery' ? holdFirst : null,
      );
      if (phase == 'configuration') {
        connector.reports = () async {
          await holdFirst();
          return true;
        };
      }
      final old = connect('old');
      await started.future;
      final replacement = await connect('replacement');
      release.complete();
      expect((await old).failure?.kind, AppConnectionFailureKind.connection);
      expect(service.session, same(replacement.session));
      final reportDirs =
          Directory('${directory.path}/.marionette/sessions').listSync();
      expect(reportDirs, hasLength(1));
    });
  }

  for (final fail in [false, true]) {
    test(
        'older disconnect ${fail ? 'failure' : 'success'} preserves replacement',
        () async {
      final first = await connect('first');
      final started = Completer<void>();
      final release = Completer<void>();
      connector.close = () {
        connector.close = null;
        started.complete();
        return release.future;
      };
      final closing = service.disconnect();
      await started.future;
      final replacement = await connect('replacement');
      if (fail) {
        release.completeError(StateError('close failed'));
      } else {
        release.complete();
      }
      final result = await closing;
      expect(result.closingSession, same(first.session));
      expect(result.error, fail ? isA<StateError>() : isNull);
      expect(service.session, same(replacement.session));
    });
  }

  test('disconnect during transport connect prevents handshake and reports',
      () async {
    final started = Completer<void>();
    final release = Completer<void>();
    connector.open = () async {
      started.complete();
      await release.future;
    };
    final pending = connect();
    await started.future;
    await service.disconnect();
    release.complete();
    final result = await pending;
    expect(result.failure?.kind, AppConnectionFailureKind.connection);
    expect(service.ownsConnection(result.generation), isFalse);
    expect(connector.configurationReads, 0);
    expect(directory.listSync(), isEmpty);
  });

  test('disposal during handshake does not run stale disconnect cleanup',
      () async {
    final started = Completer<void>();
    final release = Completer<String>();
    connector.version = () {
      started.complete();
      return release.future;
    };
    final pending = connect();
    await started.future;
    await service.dispose();
    release.completeError(StateError('socket closed'));
    final result = await pending;
    expect(result.failure?.kind, AppConnectionFailureKind.versionCheck);
    expect(connector.disconnects, 1);
    expect(service.session, isNull);
    expect(service.ownsConnection(result.generation), isFalse);
  });

  test('disposal invalidates discovery work and clears the session bridge',
      () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final sessions = <Session?>[];
    var retirements = 0;
    service = AppConnectionService(
      connector: connector,
      expectedVersion: 'fixture',
      onRetired: () => retirements++,
      onConnected: () async {
        started.complete();
        await release.future;
      },
      onSessionChanged: sessions.add,
    );
    final pending = connect();
    await started.future;
    await service.dispose();
    release.complete();
    final result = await pending;
    expect(result.failure?.kind, AppConnectionFailureKind.connection);
    expect(service.ownsConnection(result.generation), isFalse);
    expect(service.isDisposed, isTrue);
    expect(service.session, isNull);
    expect(sessions, [null, null]);
    expect(retirements, 2);
    expect(directory.listSync(), isEmpty);
  });
}

class _Connector extends VmServiceConnector {
  Future<String> Function() version = () async => 'fixture';
  Future<bool> Function() reports = () async => true;
  Future<void> Function()? close;
  Future<void> Function()? open;
  Object? connectError;
  int disconnects = 0;
  int configurationReads = 0;

  @override
  Future<void> connect(String uri) async {
    if (connectError case final error?) throw error;
    await open?.call();
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    await close?.call();
  }

  @override
  Future<String> getVersion() => version();

  @override
  Future<bool> getSessionReportsEnabled() {
    configurationReads++;
    return reports();
  }
}
