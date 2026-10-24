import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp/tools/inspection_tools.dart';
import 'package:marionette_mcp/src/session/screenshot_service.dart';
import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A single 1x1 transparent PNG, base64-encoded, standing in for a real
/// screenshot capture.
const _fakePng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

class _FakeConnector implements VmServiceConnector {
  List<String> nextScreenshots = [_fakePng];
  Object? nextError;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> takeScreenshots() async {
    calls++;
    if (nextError case final error?) throw error;
    return {'screenshots': nextScreenshots};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Extra implements RequestHandlerExtra {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final extra = _Extra();
  group('takeScreenshots', () {
    late _FakeConnector connector;
    late Directory tempDir;
    late TakeScreenshotsTool tool;
    Session? session;

    setUp(() {
      connector = _FakeConnector();
      session = null;
      tool = TakeScreenshotsTool(
        ScreenshotService(connector),
        logging.Logger.detached('test'),
        () => session,
      );
      tempDir = Directory.systemTemp.createTempSync('take_screenshots_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns inline image content by default', () async {
      final result = await tool.execute(const {}, extra);

      expect(result.isError, isFalse);
      expect(result.content, hasLength(1));
      expect((result.content.single as ImageContent).data, _fakePng);
    });

    test('reports when nothing was captured', () async {
      connector.nextScreenshots = [];
      final result = await tool.execute(const {}, extra);

      expect((result.content.single as TextContent).text,
          contains('No screenshots captured'));
    });

    test('errors when inline: false has no active session', () async {
      final result = await tool.execute(const {'inline': false}, extra);

      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('requires an active session'),
      );
    });

    test('returns connector failures before checking session requirements',
        () async {
      final error = StateError('offline');
      connector.nextError = error;

      final result = await tool.execute(const {'inline': false}, extra);

      expect(result.isError, isTrue);
      expect((result.content.single as TextContent).text, error.toString());
      expect(connector.calls, 1);
    });

    test('returns invalid image persistence failures as tool errors', () async {
      session = Session.open(Directory(p.join(tempDir.path, 'session')));
      connector.nextScreenshots = ['invalid base64'];

      final result = await tool.execute(const {'inline': false}, extra);

      expect(result.isError, isTrue);
      expect((result.content.single as TextContent).text,
          startsWith('FormatException:'));
      expect(session!.screenshotsDir.listSync(), isEmpty);
    });

    test('saves to the session screenshots directory when inline: false',
        () async {
      session = Session.open(Directory(p.join(tempDir.path, 'session')));

      final result = await tool.execute(const {'inline': false}, extra);

      expect(result.isError, isFalse);
      final savedFile = File(p.join(session!.screenshotsDir.path, '01.png'));
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsBytesSync(), base64Decode(_fakePng));
      expect((result.content.single as TextContent).text, contains('01.png'));
    });

    test('numbers subsequent saves after what is already there', () async {
      session = Session.open(Directory(p.join(tempDir.path, 'session')));
      await tool.execute(const {'inline': false}, extra);
      await tool.execute(const {'inline': false}, extra);

      expect(
        File(p.join(session!.screenshotsDir.path, '02.png')).existsSync(),
        isTrue,
      );
    });

    test('numbers past a gap without overwriting an existing screenshot',
        () async {
      // Regression test: counting PNG files (rather than looking at their
      // names) computes the wrong next index once a gap exists — e.g. after
      // 02.png is deleted, two files (01.png, 03.png) remain, and a
      // count-based index of 3 would overwrite 03.png instead of writing
      // 04.png.
      session = Session.open(Directory(p.join(tempDir.path, 'session')));
      final screenshotsDir = session!.screenshotsDir;
      File(p.join(screenshotsDir.path, '01.png')).writeAsBytesSync([1]);
      final existingThree = File(p.join(screenshotsDir.path, '03.png'))
        ..writeAsBytesSync([3]);
      final existingThreeBytesBefore = existingThree.readAsBytesSync();

      await tool.execute(const {'inline': false}, extra);

      expect(
        File(p.join(screenshotsDir.path, '04.png')).existsSync(),
        isTrue,
      );
      expect(existingThree.readAsBytesSync(), existingThreeBytesBefore);
    });
  });
}
