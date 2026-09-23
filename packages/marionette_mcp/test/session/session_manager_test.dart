import 'dart:io';

import 'package:marionette_mcp/src/session/session_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_manager_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Directory sessionsDir() =>
      Directory(p.join(tempDir.path, '.marionette', 'sessions'));

  group('createOrResume', () {
    test('creates a titled session slugified and timestamped', () {
      final manager = SessionManager();
      final session = manager.createOrResume(
        title: 'Profile Validation!',
        baseDirOverride: tempDir.path,
      );

      expect(session.resumed, isFalse);
      expect(session.name, startsWith('profile-validation-'));
      expect(session.directory.existsSync(), isTrue);
      expect(session.screenshotsDir.existsSync(), isTrue);
    });

    test('falls back to run-<timestamp> when no title is given', () {
      final manager = SessionManager();
      final session = manager.createOrResume(baseDirOverride: tempDir.path);

      expect(session.name, startsWith('run-'));
    });

    test('resumes the most recent session matching the slug', () {
      final manager = SessionManager();
      final first = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      final second = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      expect(second.resumed, isTrue);
      expect(second.directory.path, first.directory.path);
    });

    test('resumes when passed back its own exact returned name', () {
      // Regression test: the timestamp suffix embeds an uppercase "T"
      // (see _timestamp), but slugifying the title lowercases it — the
      // match must still succeed case-insensitively, or passing back
      // exactly what a previous connect returned (as documented) silently
      // creates a new session instead of resuming.
      final manager = SessionManager();
      final first = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      final second = manager.createOrResume(
        title: first.name,
        baseDirOverride: tempDir.path,
      );

      expect(second.resumed, isTrue);
      expect(second.directory.path, first.directory.path);
    });

    test('never resumes a session that already has a report.md', () {
      // Regression test: a session left over from a completed, independent
      // run must never be silently reopened (and its report.md overwritten)
      // just because a later, unrelated invocation happens to reuse the
      // same title.
      final manager = SessionManager();
      final first = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );
      File(p.join(first.directory.path, 'report.md'))
          .writeAsStringSync('Marionette report — no issues · Checkout');

      final second = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      expect(second.resumed, isFalse);
      expect(second.directory.path, isNot(equals(first.directory.path)));
    });

    test('never resumes a session that already logged a disconnect step',
        () {
      // A run can be stopped early (no report.md yet at the point checked,
      // e.g. the agent hasn't written it) but still have cleanly
      // disconnected — that alone marks it concluded too.
      final manager = SessionManager();
      final first = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );
      first.stepsFile.writeAsStringSync(
        '- [14:12:12] disconnect -> Successfully disconnected from app\n',
      );

      final second = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      expect(second.resumed, isFalse);
      expect(second.directory.path, isNot(equals(first.directory.path)));
    });

    test('a concluded session cannot be resumed even by its exact returned '
        'name', () {
      // The "pass back the exact directory name" resume path (documented on
      // the connect tool) is subject to the same rule — a concluded session
      // stays concluded regardless of which matching path found it.
      final manager = SessionManager();
      final first = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );
      File(p.join(first.directory.path, 'report.md')).writeAsStringSync('x');

      final second = manager.createOrResume(
        title: first.name,
        baseDirOverride: tempDir.path,
      );

      expect(second.resumed, isFalse);
      expect(second.directory.path, isNot(equals(first.directory.path)));
    });

    test('still resumes a session with no report.md and no disconnect yet',
        () {
      // The common, legitimate case: the run was cut short (compaction,
      // interruption) before reaching either conclusion signal.
      final manager = SessionManager();
      final first = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );
      first.stepsFile.writeAsStringSync('- [14:12:03] connect -> ok\n');

      final second = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      expect(second.resumed, isTrue);
      expect(second.directory.path, first.directory.path);
    });

    test('a fresh title never resumes an untitled run', () {
      final manager = SessionManager();
      manager.createOrResume(baseDirOverride: tempDir.path);
      final second = manager.createOrResume(baseDirOverride: tempDir.path);

      expect(second.resumed, isFalse);
    });

    test('two untitled sessions created back-to-back get distinct '
        'directories', () {
      // Regression test: untitled runs are only unique to the minute
      // (_timestamp has no seconds). Without disambiguation, two untitled
      // connects within the same minute would resolve to the identical
      // directory name and — since Directory.createSync doesn't error on an
      // already-existing directory — the second would silently share (and
      // corrupt) the first's steps.md while still reporting resumed: false.
      final manager = SessionManager();
      final first = manager.createOrResume(baseDirOverride: tempDir.path);
      final second = manager.createOrResume(baseDirOverride: tempDir.path);

      expect(second.directory.path, isNot(equals(first.directory.path)));
      expect(second.resumed, isFalse);
    });

    test('a title never resumes an unrelated session that merely shares '
        'its slug as a prefix', () {
      // Regression test: a bare prefix match on the directory name would
      // let "checkout" resume an unrelated "checkout flow" session (its
      // slug "checkout-flow" starts with "checkout-"), and would let a
      // title of "run" collide with every untitled run-<timestamp>
      // fallback session.
      final manager = SessionManager();
      final unrelated = manager.createOrResume(
        title: 'Checkout flow',
        baseDirOverride: tempDir.path,
      );

      final result = manager.createOrResume(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      expect(result.resumed, isFalse);
      expect(result.directory.path, isNot(equals(unrelated.directory.path)));

      final untitled = manager.createOrResume(baseDirOverride: tempDir.path);
      final titledRun = manager.createOrResume(
        title: 'run',
        baseDirOverride: tempDir.path,
      );

      expect(titledRun.resumed, isFalse);
      expect(
        titledRun.directory.path,
        isNot(equals(untitled.directory.path)),
      );
    });

    test('resuming a slug prefers the candidate with the most recent step '
        'over one with a merely newer directory mtime', () async {
      // Regression test: appending to steps.md never bumps its parent
      // directory's own mtime on any common filesystem, so sorting
      // candidates on the directory's mtime treats a heavily-used session
      // as stale the moment a newer, otherwise-idle directory with the same
      // slug marker appears — wrongly resuming (or pruning) the wrong one.
      // Two directories can only carry the same slug marker by fabricating
      // one by hand here — createOrResume itself always resumes rather than
      // duplicate a slug it already knows about.
      final active = Directory(p.join(sessionsDir().path, 'active-first'))
        ..createSync(recursive: true);
      File(p.join(active.path, '.session-slug')).writeAsStringSync('active');
      File(
        p.join(active.path, 'steps.md'),
      ).writeAsStringSync('- [00:00:00] connect -> ok\n');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // A directory created *after* `active`'s last step, but never used
      // itself. Its own mtime is later than `active`'s directory mtime,
      // even though `active` is the one that's actually still in use.
      final idle = Directory(p.join(sessionsDir().path, 'active-second'))
        ..createSync(recursive: true);
      File(p.join(idle.path, '.session-slug')).writeAsStringSync('active');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // `active` logs another step — later in wall-clock time than
      // `idle`'s directory was created, even though `active`'s own
      // directory mtime (unaffected by the append) still predates it.
      File(p.join(active.path, 'steps.md')).writeAsStringSync(
        '- [00:00:01] tap key=x -> ok\n',
        mode: FileMode.append,
      );

      final manager = SessionManager();
      final resumed = manager.createOrResume(
        title: 'active',
        baseDirOverride: tempDir.path,
      );

      expect(resumed.resumed, isTrue);
      expect(resumed.directory.path, active.path);
    });

    test('resolves the base directory from the env-var-free override first',
        () {
      final manager = SessionManager();
      final session = manager.createOrResume(
        title: 'x',
        baseDirOverride: tempDir.path,
      );

      expect(
        p.isWithin(sessionsDir().path, session.directory.path),
        isTrue,
      );
    });

    test('prunes sessions beyond maxSessions, keeping the active one',
        () async {
      final manager = SessionManager(maxSessions: 2);
      // A real gap between creations (rather than relying on best-effort
      // ordering within the same filesystem timestamp resolution window)
      // keeps pruning's "most recently modified" comparison deterministic.
      final a =
          manager.createOrResume(title: 'a', baseDirOverride: tempDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final b =
          manager.createOrResume(title: 'b', baseDirOverride: tempDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final third =
          manager.createOrResume(title: 'c', baseDirOverride: tempDir.path);

      final remaining = sessionsDir()
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .toSet();

      expect(remaining, hasLength(2));
      expect(remaining, containsAll([third.name, b.name]));
      expect(remaining, isNot(contains(a.name)));
    });
  });
}
