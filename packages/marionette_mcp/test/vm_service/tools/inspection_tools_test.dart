import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/vm_service/tools/inspection_tools.dart';
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

  @override
  Future<Map<String, dynamic>> takeScreenshots() async =>
      {'screenshots': nextScreenshots};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('takeScreenshots', () {
    late _FakeConnector connector;
    late Directory tempDir;

    setUp(() {
      connector = _FakeConnector();
      tempDir = Directory.systemTemp.createTempSync('take_screenshots_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns inline image content by default', () async {
      final result = await takeScreenshots(connector, null, const {});

      expect(result.isError, isFalse);
      expect(result.content, hasLength(1));
      expect((result.content.single as ImageContent).data, _fakePng);
    });

    test('reports when nothing was captured', () async {
      connector.nextScreenshots = [];
      final result = await takeScreenshots(connector, null, const {});

      expect((result.content.single as TextContent).text,
          contains('No screenshots captured'));
    });

    test('errors when inline: false has no active session', () async {
      final result =
          await takeScreenshots(connector, null, const {'inline': false});

      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('requires an active session'),
      );
    });

    test('saves to the session screenshots directory when inline: false',
        () async {
      final session = Session.open(Directory(p.join(tempDir.path, 'session')));

      final result =
          await takeScreenshots(connector, session, const {'inline': false});

      expect(result.isError, isFalse);
      final savedFile = File(p.join(session.screenshotsDir.path, '01.png'));
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsBytesSync(), base64Decode(_fakePng));
      expect((result.content.single as TextContent).text, contains('01.png'));
    });

    test('numbers subsequent saves after what is already there', () async {
      final session = Session.open(Directory(p.join(tempDir.path, 'session')));
      await takeScreenshots(connector, session, const {'inline': false});
      await takeScreenshots(connector, session, const {'inline': false});

      expect(
        File(p.join(session.screenshotsDir.path, '02.png')).existsSync(),
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
      final session = Session.open(Directory(p.join(tempDir.path, 'session')));
      final screenshotsDir = session.screenshotsDir;
      File(p.join(screenshotsDir.path, '01.png')).writeAsBytesSync([1]);
      final existingThree = File(p.join(screenshotsDir.path, '03.png'))
        ..writeAsBytesSync([3]);
      final existingThreeBytesBefore = existingThree.readAsBytesSync();

      await takeScreenshots(connector, session, const {'inline': false});

      expect(
        File(p.join(screenshotsDir.path, '04.png')).existsSync(),
        isTrue,
      );
      expect(existingThree.readAsBytesSync(), existingThreeBytesBefore);
    });
  });
}
