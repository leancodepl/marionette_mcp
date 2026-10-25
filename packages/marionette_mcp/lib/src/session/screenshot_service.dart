import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:path/path.dart' as p;

import 'session.dart';

/// Captures application screenshots and optionally persists them in a session.
class ScreenshotService {
  ScreenshotService(this.connector);

  final VmServiceConnector connector;

  /// Captures all views, returning inline images or the saved image paths.
  ///
  /// Empty captures succeed without a session. Nonempty save-only captures
  /// require [session], which is retained throughout this operation.
  Future<ScreenshotCapture> capture({
    required bool inline,
    Session? session,
  }) async {
    final response = await connector.takeScreenshots();
    final images = (response['screenshots'] as List<dynamic>).cast<String>();
    if (images.isEmpty || inline) {
      return ScreenshotCapture._(
        count: images.length,
        inline: inline,
        images: images,
      );
    }
    if (session == null) throw const ScreenshotSessionRequired();

    final paths = _saveScreenshots(session.screenshotsDir, images);
    return ScreenshotCapture._(
      count: paths.length,
      inline: false,
      paths: paths,
    );
  }
}

/// Immutable capture data, containing base64 PNG images or persisted paths.
class ScreenshotCapture {
  ScreenshotCapture._({
    required this.count,
    required this.inline,
    List<String> images = const [],
    List<String> paths = const [],
  })  : images = List.unmodifiable(images),
        paths = List.unmodifiable(paths);

  final int count;
  final bool inline;

  /// Base64-encoded PNG images for inline captures.
  final List<String> images;

  /// Files written for save-only captures.
  final List<String> paths;
}

/// A nonempty save-only capture was requested without an active session.
class ScreenshotSessionRequired implements Exception {
  const ScreenshotSessionRequired();
}

List<String> _saveScreenshots(
  Directory screenshotsDir,
  List<String> screenshots,
) {
  screenshotsDir.createSync(recursive: true);
  // Use the highest numeric name rather than the file count: deleted images
  // leave gaps that must not cause existing captures to be overwritten.
  final highestExisting = screenshotsDir
      .listSync()
      .whereType<File>()
      .where((f) => p.extension(f.path) == '.png')
      .map((f) => int.tryParse(p.basenameWithoutExtension(f.path)))
      .whereType<int>()
      .fold(0, (highest, n) => n > highest ? n : highest);
  var nextIndex = highestExisting + 1;

  final paths = <String>[];
  for (final screenshot in screenshots) {
    final path = p.join(
      screenshotsDir.path,
      '${nextIndex.toString().padLeft(2, '0')}.png',
    );
    File(path).writeAsBytesSync(base64Decode(screenshot));
    paths.add(path);
    nextIndex++;
  }
  return paths;
}
