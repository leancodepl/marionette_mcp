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

    test('a fresh title never resumes an untitled run', () {
      final manager = SessionManager();
      manager.createOrResume(baseDirOverride: tempDir.path);
      final second = manager.createOrResume(baseDirOverride: tempDir.path);

      expect(second.resumed, isFalse);
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
