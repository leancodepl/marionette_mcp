import 'dart:io';

import 'package:path/path.dart' as p;

/// A single Marionette run's persistent workspace: a directory under
/// `.marionette/sessions/` holding the machine-appended step log and any
/// saved screenshots.
///
/// `report.md` and `report-full.md` live here too but are written by the
/// connected agent using its own file tools, not by this class — [Session]
/// only owns the directory layout and the paths.
class Session {
  Session._({required this.directory, required this.resumed});

  /// Creates the session directory (and its `screenshots/` subdirectory) if
  /// they don't already exist, and returns a [Session] for it.
  factory Session.open(Directory directory, {required bool resumed}) {
    directory.createSync(recursive: true);
    Directory(
      p.join(directory.path, 'screenshots'),
    ).createSync(recursive: true);
    return Session._(directory: directory, resumed: resumed);
  }

  /// The session directory, e.g. `.marionette/sessions/profile-validation-20260922T1412`.
  final Directory directory;

  /// Whether an existing session directory was reused rather than created.
  final bool resumed;

  /// The session's directory name, e.g. `profile-validation-20260922T1412`.
  String get name => p.basename(directory.path);

  /// Appended by the server, one line per tool call.
  File get stepsFile => File(p.join(directory.path, 'steps.md'));

  /// Where `take_screenshots` (with `inline: false`) saves captures.
  Directory get screenshotsDir =>
      Directory(p.join(directory.path, 'screenshots'));

  /// Written once at the end by the connected agent.
  File get reportFile => File(p.join(directory.path, 'report.md'));

  /// Appended by the agent during the run once past the materialization
  /// threshold (a pause, a resume, or more than one check).
  File get reportFullFile => File(p.join(directory.path, 'report-full.md'));
}
