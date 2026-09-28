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

  group('create', () {
    test('creates a titled session slugified and timestamped', () {
      final manager = SessionManager();
      final session = manager.create(
        title: 'Profile Validation!',
        baseDirOverride: tempDir.path,
      );

      expect(session.name, startsWith('profile-validation-'));
      expect(session.directory.existsSync(), isTrue);
      expect(session.screenshotsDir.existsSync(), isTrue);
    });

    test('falls back to run-<timestamp> when no title is given', () {
      final manager = SessionManager();
      final session = manager.create(baseDirOverride: tempDir.path);

      expect(session.name, startsWith('run-'));
    });

    test('a repeated title never reuses the previous directory', () {
      final manager = SessionManager();
      final first = manager.create(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      final second = manager.create(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      expect(second.directory.path, isNot(equals(first.directory.path)));
    });

    test('passing back its own exact returned name never reuses it', () {
      final manager = SessionManager();
      final first = manager.create(
        title: 'Checkout',
        baseDirOverride: tempDir.path,
      );

      final second = manager.create(
        title: first.name,
        baseDirOverride: tempDir.path,
      );

      expect(second.directory.path, isNot(equals(first.directory.path)));
    });

    test('two sessions created back-to-back get distinct directories', () {
      // Regression test: sessions are only unique to the minute (_timestamp
      // has no seconds). Without disambiguation, two connects within the
      // same minute would resolve to the identical directory name and —
      // since Directory.createSync doesn't error on an already-existing
      // directory — the second would silently share (and corrupt) the
      // first's steps.md.
      final manager = SessionManager();
      final first = manager.create(baseDirOverride: tempDir.path);
      final second = manager.create(baseDirOverride: tempDir.path);

      expect(second.directory.path, isNot(equals(first.directory.path)));
    });

    test('writes a .gitignore excluding .marionette/ from version control',
        () {
      final manager = SessionManager();
      manager.create(title: 'x', baseDirOverride: tempDir.path);

      final gitignore = File(
        p.join(tempDir.path, '.marionette', '.gitignore'),
      );
      expect(gitignore.existsSync(), isTrue);
      expect(gitignore.readAsStringSync().trim(), '*');
    });

    test('never overwrites an existing .marionette/.gitignore', () {
      final marionetteDir = Directory(p.join(tempDir.path, '.marionette'))
        ..createSync(recursive: true);
      File(
        p.join(marionetteDir.path, '.gitignore'),
      ).writeAsStringSync('custom\n');

      SessionManager().create(title: 'x', baseDirOverride: tempDir.path);

      expect(
        File(p.join(marionetteDir.path, '.gitignore')).readAsStringSync(),
        'custom\n',
      );
    });

    test('resolves the base directory from the env-var-free override first',
        () {
      final manager = SessionManager();
      final session = manager.create(
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
      final a = manager.create(title: 'a', baseDirOverride: tempDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final b = manager.create(title: 'b', baseDirOverride: tempDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final third = manager.create(title: 'c', baseDirOverride: tempDir.path);

      final remaining = sessionsDir()
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .toSet();

      expect(remaining, hasLength(2));
      expect(remaining, containsAll([third.name, b.name]));
      expect(remaining, isNot(contains(a.name)));
    });

    test('never prunes a session directory that already has a report.md',
        () async {
      // Regression test: pruning is pure LRU across every session
      // directory, regardless of which transport (MCP or CLI) created it.
      // Without this guard, enough newer one-line CLI sessions could evict
      // an older, already-concluded MCP session — deleting its report.md.
      final manager = SessionManager(maxSessions: 2);
      final a = manager.create(title: 'a', baseDirOverride: tempDir.path);
      File(p.join(a.directory.path, 'report.md')).writeAsStringSync('done');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      manager.create(title: 'b', baseDirOverride: tempDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      manager.create(title: 'c', baseDirOverride: tempDir.path);

      expect(a.directory.existsSync(), isTrue);
    });
  });
}
