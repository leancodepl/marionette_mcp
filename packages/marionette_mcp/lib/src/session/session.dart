import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A single Marionette run's persistent workspace: a directory under
/// `.marionette/sessions/` holding the machine-appended step log and any
/// saved screenshots.
///
/// `report.md` lives here too but is written by the connected agent using
/// its own file tools, not by this class — [Session] only owns the
/// directory layout and the paths.
class Session {
  Session._({required this.directory});

  /// Creates the session directory (and its `screenshots/` subdirectory),
  /// and returns a [Session] for it.
  factory Session.open(Directory directory) {
    directory.createSync(recursive: true);
    Directory(
      p.join(directory.path, 'screenshots'),
    ).createSync(recursive: true);
    return Session._(directory: directory);
  }

  /// The session directory, e.g. `.marionette/sessions/profile-validation-20260922T1412`.
  final Directory directory;

  /// The session's directory name, e.g. `profile-validation-20260922T1412`.
  String get name => p.basename(directory.path);

  /// Appended by the server, one line per tool call.
  File get stepsFile => File(p.join(directory.path, 'steps.md'));

  /// Where `take_screenshots` and `native_take_screenshot` (with
  /// `inline: false`) save captures.
  Directory get screenshotsDir =>
      Directory(p.join(directory.path, 'screenshots'));

  /// Saves each base64-encoded PNG in [screenshots] into [screenshotsDir],
  /// numbered sequentially after whatever is already there, and returns the
  /// paths written to — for `take_screenshots` and `native_take_screenshot`
  /// with `inline: false`.
  List<String> saveScreenshots(List<String> screenshots) {
    screenshotsDir.createSync(recursive: true);
    // The next index is one past the highest existing numeric name, not a
    // count of PNGs present — a gap (e.g. 01.png and 03.png after 02.png was
    // deleted) would otherwise make a count-based index collide with, and
    // overwrite, the existing 03.png.
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
}
