import 'dart:io';

import 'package:marionette_mcp/src/session/session.dart';
import 'package:marionette_mcp/src/session/session_manager.dart';

/// Creates the session directory a CLI command logs its step into. A
/// directory that cannot be created only warns on stderr and returns null:
/// the command still runs, without a step log.
Session? createCliStepSession({String? title, String? baseDirOverride}) {
  try {
    return SessionManager()
        .create(title: title, baseDirOverride: baseDirOverride);
  } on FileSystemException catch (e) {
    stderr.writeln(
      'Warning: could not open a session directory, so this run will not be '
      'logged: $e',
    );
    return null;
  }
}

/// Appends [line] to the steps.md of [session], for a CLI command. A failed
/// write only warns on stderr: the command has already run.
void appendStepLine(Session session, String line) {
  try {
    session.stepsFile.writeAsStringSync('$line\n', mode: FileMode.append);
  } on FileSystemException catch (e) {
    stderr.writeln('Warning: could not write to steps.md: $e');
  }
}
