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

/// Creates and resumes session directories under `.marionette/sessions/`,
/// and prunes old ones so the directory doesn't grow without bound.
class SessionManager {
  SessionManager({this.maxSessions = defaultMaxSessions});

  final int maxSessions;

  /// Creates a fresh session directory, or resumes the most recently used
  /// one whose name matches the slugified [title] — this is how a run
  /// survives a compaction, an interruption, or an explicit resume: pass the
  /// same `session_title` again.
  ///
  /// [baseDirOverride] (a `connect` argument) takes priority over the
  /// [sessionDirEnvVar] environment variable; if neither is set, the base
  /// directory falls back to the process's current directory.
  Session createOrResume({String? title, String? baseDirOverride}) {
    final sessionsDir = Directory(
      p.join(_resolveBaseDir(baseDirOverride), '.marionette', 'sessions'),
    )..createSync(recursive: true);

    final slug = _slugify(title);
    final existing = slug == null ? null : _mostRecentMatch(sessionsDir, slug);

    final session = existing != null
        ? Session.open(existing, resumed: true)
        : Session.open(
            Directory(
              p.join(sessionsDir.path, '${slug ?? 'run'}-${_timestamp()}'),
            ),
            resumed: false,
          );

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

  /// The most recently modified directory named exactly [slug] or prefixed
  /// with `$slug-` (a slug followed by a creation timestamp), compared
  /// case-insensitively — [slug] is always lowercase (see [_slugify]), but a
  /// directory name embeds a timestamp with an uppercase `T` (see
  /// [_timestamp]), so passing back a previous connect's exact returned name
  /// must still match it.
  Directory? _mostRecentMatch(Directory sessionsDir, String slug) {
    final matches = sessionsDir.listSync().whereType<Directory>().where((d) {
      final name = p.basename(d.path).toLowerCase();
      return name == slug || name.startsWith('$slug-');
    }).toList()
      ..sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
    return matches.isEmpty ? null : matches.first;
  }

  /// Deletes every session directory beyond the [maxSessions] most recently
  /// modified, never the directory at [keep].
  void _prune(Directory sessionsDir, {required String keep}) {
    final dirs = sessionsDir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path != keep)
        .toList()
      ..sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
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
