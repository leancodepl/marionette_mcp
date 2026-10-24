import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/session/screenshot_service.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Connector implements VmServiceConnector {
  List<String> images = ['aGVsbG8='];
  int calls = 0;
  Completer<Map<String, dynamic>>? pending;
  Object? error;

  @override
  Future<Map<String, dynamic>> takeScreenshots() async {
    calls++;
    if (error case final error?) throw error;
    return pending?.future ?? {'screenshots': images};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _Connector connector;
  late ScreenshotService service;
  late Directory directory;

  setUp(() {
    connector = _Connector();
    service = ScreenshotService(connector);
    directory = Directory.systemTemp.createTempSync('screenshot-service-');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('inline capture returns immutable base64 images without a session',
      () async {
    final result = await service.capture(inline: true);
    expect(result.count, 1);
    expect(result.inline, isTrue);
    expect(result.images, ['aGVsbG8=']);
    expect(result.paths, isEmpty);
    connector.images.add('d29ybGQ=');
    expect(result.images, ['aGVsbG8=']);
    expect(() => result.images.add('other'), throwsUnsupportedError);
    expect(directory.listSync(), isEmpty);
  });

  test('empty capture preserves either inline mode without a session',
      () async {
    connector.images = [];
    for (final inline in [true, false]) {
      final result = await service.capture(inline: inline);
      expect(result.count, 0);
      expect(result.inline, inline);
      expect(result.images, isEmpty);
      expect(result.paths, isEmpty);
    }
    expect(connector.calls, 2);
  });

  test('save-only captures persist decoded images in the session', () async {
    connector.images = ['aGVsbG8=', 'd29ybGQ='];
    final session = Session.open(directory);
    final result = await service.capture(inline: false, session: session);
    expect(result.count, 2);
    expect(result.inline, isFalse);
    expect(result.images, isEmpty);
    expect(result.paths, [
      p.join(session.screenshotsDir.path, '01.png'),
      p.join(session.screenshotsDir.path, '02.png'),
    ]);
    expect(File(result.paths[0]).readAsBytesSync(), utf8.encode('hello'));
    expect(File(result.paths[1]).readAsBytesSync(), utf8.encode('world'));
    expect(() => result.paths.clear(), throwsUnsupportedError);
  });

  test('nonempty save-only capture requires a session after capture', () async {
    await expectLater(
      service.capture(inline: false),
      throwsA(isA<ScreenshotSessionRequired>()),
    );
    expect(connector.calls, 1);
    expect(directory.listSync(), isEmpty);
  });

  test('numbering continues after highest numeric PNG and preserves gaps',
      () async {
    final session = Session.open(directory);
    final screenshotsDir = session.screenshotsDir;
    for (final name in ['01.png', '03.png', 'other.png', '100.txt']) {
      File(p.join(screenshotsDir.path, name)).writeAsStringSync('existing');
    }
    Directory(p.join(screenshotsDir.path, '200.png')).createSync();
    final first = await service.capture(inline: false, session: session);
    final second = await service.capture(inline: false, session: session);
    expect(first.paths.single, p.join(screenshotsDir.path, '04.png'));
    expect(second.paths.single, p.join(screenshotsDir.path, '05.png'));
    for (final name in ['01.png', '03.png', 'other.png', '100.txt']) {
      expect(File(p.join(screenshotsDir.path, name)).readAsStringSync(),
          'existing');
    }
    expect(File(p.join(screenshotsDir.path, '02.png')).existsSync(), isFalse);
  });

  test('capture retains the supplied session across the connector await',
      () async {
    var currentSession =
        Session.open(Directory(p.join(directory.path, 'first')));
    final capturedSession = currentSession;
    connector.pending = Completer<Map<String, dynamic>>();
    final capture = service.capture(inline: false, session: currentSession);
    currentSession = Session.open(Directory(p.join(directory.path, 'second')));
    connector.pending!.complete({
      'screenshots': ['aGVsbG8='],
    });
    final result = await capture;
    expect(result.paths.single,
        p.join(capturedSession.screenshotsDir.path, '01.png'));
    expect(currentSession.screenshotsDir.listSync(), isEmpty);
  });

  test('connector failures propagate before checking session requirements',
      () async {
    final error = StateError('offline');
    connector.error = error;
    await expectLater(service.capture(inline: false), throwsA(same(error)));
    expect(connector.calls, 1);
  });

  test('invalid image data propagates from persistence', () async {
    connector.images = ['invalid base64'];
    await expectLater(
      service.capture(inline: false, session: Session.open(directory)),
      throwsFormatException,
    );
  });
}
