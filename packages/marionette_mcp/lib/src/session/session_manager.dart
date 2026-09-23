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

/// Name of the marker file a titled session directory carries, recording the
/// exact slug it was created under. Resuming by title reads this back rather
/// than guessing from the directory name — a bare prefix match on the name
/// would let a title of "checkout" resume an unrelated "checkout-flow-..."
/// session, or a title of "run" collide with every untitled fallback
/// session (which also names its directory `run-<timestamp>`).
const _slugMarkerFileName = '.session-slug';

/// Matches a `disconnect` line in `steps.md`, e.g.
/// `- [14:12:12] disconnect -> Successfully disconnected from app...` —
/// `disconnect` never has a selector (see `describeStepSelector`), so this
/// is always the exact shape a logged disconnect step takes.
final _disconnectStepLine = RegExp(r'^- \[\d\d:\d\d:\d\d\] disconnect -> ');

/// Creates and resumes session directories under `.marionette/sessions/`,
/// and prunes old ones so the directory doesn't grow without bound.
class SessionManager {
  SessionManager({this.maxSessions = defaultMaxSessions});

  final int maxSessions;

  /// Creates a fresh session directory, or resumes the most recently used
  /// one matching the slugified [title] — this is how a run survives a
  /// compaction, an interruption, or an explicit resume: pass the same
  /// `session_title` again. A session that's already concluded (see
  /// [_isConcluded]) is never resumed, even by an exact title or directory-
  /// name match: a fresh directory is created instead, so a later,
  /// unrelated invocation that happens to reuse the same title can never
  /// silently append to — or worse, have its own later `report.md` shadow —
  /// an already-finished run's session.
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

    final Session session;
    if (existing != null) {
      session = Session.open(existing, resumed: true);
    } else {
      final directory = _freshDirectory(
        sessionsDir,
        '${slug ?? 'run'}-${_timestamp()}',
      );
      session = Session.open(directory, resumed: false);
      if (slug != null) {
        File(
          p.join(directory.path, _slugMarkerFileName),
        ).writeAsStringSync(slug);
      }
    }

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

  /// The most recently used directory matching [slug]: either its own name
  /// equals [slug] (resuming by the exact directory name a previous connect
  /// returned), or it carries a [_slugMarkerFileName] recording it was
  /// created under [slug] (resuming by the same short title). Never a bare
  /// prefix match on the directory name — see [_slugMarkerFileName]. Skips
  /// any candidate that's already concluded — see [_isConcluded].
  Directory? _mostRecentMatch(Directory sessionsDir, String slug) {
    final matches = sessionsDir
        .listSync()
        .whereType<Directory>()
        .where((d) => _matchesSlug(d, slug) && !_isConcluded(d))
        .toList()
      ..sort((a, b) => _lastUsed(b).compareTo(_lastUsed(a)));
    return matches.isEmpty ? null : matches.first;
  }

  bool _matchesSlug(Directory dir, String slug) {
    if (p.basename(dir.path).toLowerCase() == slug) return true;
    return _readSlugMarker(dir) == slug;
  }

  /// Whether [dir] has already reached a conclusion: `disconnect` logged its
  /// own step in `steps.md` (the server's own, tamper-proof record that this
  /// run was cleanly closed), or `report.md` exists (the agent's own sign
  /// that it considered the run — or an early stop — final; the contract
  /// requires writing it on either trigger). Either one means there's a
  /// finished artifact here worth protecting, so this directory is never
  /// offered as a resume candidate again — a later, independent invocation
  /// that happens to reuse the same title gets its own fresh directory
  /// instead of silently reopening and overwriting a closed one.
  bool _isConcluded(Directory dir) {
    if (File(p.join(dir.path, 'report.md')).existsSync()) return true;
    final stepsFile = File(p.join(dir.path, 'steps.md'));
    if (!stepsFile.existsSync()) return false;
    return stepsFile.readAsLinesSync().any(_disconnectStepLine.hasMatch);
  }

  String? _readSlugMarker(Directory dir) {
    final marker = File(p.join(dir.path, _slugMarkerFileName));
    if (!marker.existsSync()) return null;
    final slug = marker.readAsStringSync().trim();
    return slug.isEmpty ? null : slug;
  }

  /// A directory named [baseName] under [sessionsDir], disambiguated with a
  /// numeric suffix if that name is already taken — e.g. two untitled
  /// sessions created within the same timestamp-resolution window (minute
  /// granularity), which would otherwise silently share one directory while
  /// both report `resumed: false`.
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
  /// session has logged anything — appending to a file never bumps its
  /// parent directory's mtime on any common filesystem, so sorting on the
  /// directory's own mtime would treat a heavily-used, resumed session as
  /// stale — falling back to the directory's mtime for one that hasn't
  /// logged a step yet.
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
