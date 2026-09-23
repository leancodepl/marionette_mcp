import 'dart:io';

import 'package:marionette_mcp/src/session/session.dart';
import 'package:path/path.dart' as p;

/// Environment variable an MCP client sets to the project directory session
/// reports should live under. Read instead of the process's working
/// directory, which an MCP host does not reliably set to the repo root.
const sessionDirEnvVar = 'MARIONETTE_SESSION_DIR';

/// Number of most-recently-used session directories kept per project;
/// older ones are deleted the next time a session is created.
const defaultMaxSessions = 20;

/// Creates session directories under `.marionette/sessions/`, and prunes old
/// ones so the directory doesn't grow without bound.
class SessionManager {
  SessionManager({this.maxSessions = defaultMaxSessions});

  final int maxSessions;

  /// Creates a fresh session directory, named from the slugified [title] and
  /// a creation timestamp. One `connect` always produces exactly one session
  /// directory — there is no resuming: a title is purely a human-readable
  /// label, never a lookup key.
  ///
  /// [baseDirOverride] (a `connect` argument) takes priority over the
  /// [sessionDirEnvVar] environment variable; if neither is set, the base
  /// directory falls back to the process's current directory.
  Session create({String? title, String? baseDirOverride}) {
    final sessionsDir = Directory(
      p.join(_resolveBaseDir(baseDirOverride), '.marionette', 'sessions'),
    )..createSync(recursive: true);

    final slug = _slugify(title);
    final directory = _freshDirectory(
      sessionsDir,
      '${slug ?? 'run'}-${_timestamp()}',
    );
    final session = Session.open(directory);

    _prune(sessionsDir, keep: session.directory.path);
    return session;
  }

  String _resolveBaseDir(String? baseDirOverride) {
    if (baseDirOverride != null && baseDirOverride.trim().isNotEmpty) {
      return baseDirOverride;
    }
    final envDir = Platform.environment[sessionDirEnvVar];
    if (envDir != null && envDir.trim().isNotEmpty) return envDir;
    return Directory.current.path;
  }

  /// A directory named [baseName] under [sessionsDir], disambiguated with a
  /// numeric suffix if that name is already taken — e.g. two sessions
  /// created within the same timestamp-resolution window (minute
  /// granularity), which would otherwise silently share one directory.
  Directory _freshDirectory(Directory sessionsDir, String baseName) {
    var candidate = Directory(p.join(sessionsDir.path, baseName));
    var suffix = 2;
    while (candidate.existsSync()) {
      candidate = Directory(p.join(sessionsDir.path, '$baseName-$suffix'));
      suffix++;
    }
    return candidate;
  }

  /// The most recent activity in [dir]: steps.md's own mtime once the
  /// session has logged anything, falling back to the directory's mtime for
  /// one that hasn't logged a step yet.
  DateTime _lastUsed(Directory dir) {
    final stepsFile = File(p.join(dir.path, 'steps.md'));
    if (stepsFile.existsSync()) return stepsFile.statSync().modified;
    return dir.statSync().modified;
  }

  /// Deletes every session directory beyond the [maxSessions] most recently
  /// used (see [_lastUsed]), never the directory at [keep].
  void _prune(Directory sessionsDir, {required String keep}) {
    final dirs = sessionsDir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path != keep)
        .toList()
      ..sort((a, b) => _lastUsed(b).compareTo(_lastUsed(a)));
    final keepOthers = maxSessions > 0 ? maxSessions - 1 : 0;
    for (final dir in dirs.skip(keepOthers)) {
      dir.deleteSync(recursive: true);
    }
  }

  String? _slugify(String? title) {
    if (title == null) return null;
    final slug = title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? null : slug;
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        'T${two(now.hour)}${two(now.minute)}';
  }
}
