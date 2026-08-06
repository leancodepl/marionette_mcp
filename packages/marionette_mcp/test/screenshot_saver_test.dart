import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_mcp/src/screenshot_saver.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

void main() {
  group('MARIONETTE_SCREENSHOTS_DIR resolution', () {
    test('saveScreenshotPng returns null when env is unset', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
      final file = saveScreenshotPng(
        base64Encode(bytes),
        suffix: 'native',
        environment: const {},
      );
      expect(file, isNull);
    });

    test('saveScreenshotPng returns null when env is empty', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
      final file = saveScreenshotPng(
        base64Encode(bytes),
        suffix: 'native',
        environment: const {screenshotsDirEnvKey: '   '},
      );
      expect(file, isNull);
    });

    test('saveScreenshotPng honors MARIONETTE_SCREENSHOTS_DIR override', () {
      final tempDir =
          Directory.systemTemp.createTempSync('marionette_env_shots_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
      final file = saveScreenshotPng(
        base64Encode(bytes),
        suffix: 'native',
        environment: {screenshotsDirEnvKey: tempDir.path},
        clock: DateTime.utc(2026, 8, 5, 11, 22, 33),
      );

      expect(file, isNotNull);
      expect(file!.parent.path, tempDir.path);
      expect(file.existsSync(), isTrue);
    });
  });

  group('saveScreenshotPng', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('marionette_shots_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns null when no directory is configured', () {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
      final b64 = base64Encode(bytes);

      final file = saveScreenshotPng(b64, suffix: 'native');

      expect(file, isNull);
    });

    test('writes decoded bytes and returns absolute path', () {
      // Minimal valid-looking payload — saver does not validate PNG structure.
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
      final b64 = base64Encode(bytes);
      final clock = DateTime.utc(2026, 8, 5, 11, 22, 33);

      final file = saveScreenshotPng(
        b64,
        suffix: 'native',
        screenshotsDirectory: tempDir,
        clock: clock,
      );

      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(file.readAsBytesSync(), bytes);
      expect(
        file.path,
        endsWith('2026-08-05T11-22-33.000Z_native.png'),
      );
      expect(file.absolute.path, file.path);
    });
  });

  group('screenshotToolContent', () {
    test('includes saved path text and image content when file is saved', () {
      final file = File('/tmp/example.png');
      final content = screenshotToolContent(
        pngBase64: 'abc',
        savedFile: file,
      );

      expect(content, hasLength(2));
      final text = content[0] as TextContent;
      expect(text.text, contains(file.absolute.path));
      expect(text.text, contains('![]('));
      final image = content[1] as ImageContent;
      expect(image.data, 'abc');
      expect(image.mimeType, 'image/png');
    });

    test('returns only image content when file is not saved', () {
      final content = screenshotToolContent(
        pngBase64: 'abc',
        savedFile: null,
      );

      expect(content, hasLength(1));
      final image = content[0] as ImageContent;
      expect(image.data, 'abc');
      expect(image.mimeType, 'image/png');
    });
  });
}
