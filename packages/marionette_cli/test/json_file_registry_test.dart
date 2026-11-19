import 'dart:io';
import 'dart:isolate';

import 'package:marionette_cli/src/json_file_registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late _Registry registry;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('marionette_registry_test_');
    registry = _Registry(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('JsonFileRegistry.validateName', () {
    test('accepts valid names', () {
      for (final name in [
        'my-app',
        'app_1',
        'ABC123',
        'a',
        'test-app-2',
        'my app',
        'app@1',
        '192.168.240.112:5555',
        'my.device.local',
      ]) {
        expect(
          () => JsonFileRegistry.validateName(name),
          returnsNormally,
          reason: 'Expected "$name" to be valid',
        );
      }
    });

    test('rejects invalid names', () {
      for (final name in [
        '',
        'app/bad',
        '../../etc',
        'a\\b',
        'app\u0000name',
        'app\nname',
        'app\rname',
        'app\tname',
        'app\u001Bname', // ESC
        'app\u007Fname', // DEL
      ]) {
        expect(
          () => JsonFileRegistry.validateName(name),
          throwsA(isA<FormatException>()),
          reason: 'Expected "$name" to be invalid',
        );
      }
    });

    test('accepts a name whose encoded file name is exactly at the limit', () {
      final name = 'a' * 250; // + '.json' (5 chars) = 255
      expect(() => JsonFileRegistry.validateName(name), returnsNormally);
    });

    test('rejects a name whose raw length alone exceeds the limit', () {
      final name = 'a' * 251; // + '.json' (5 chars) = 256
      expect(
        () => JsonFileRegistry.validateName(name),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a short name that percent-encoding inflates past the limit',
        () {
      // Each '😀' is a 4-byte UTF-8 character encoding to 12 chars
      // (`%XX%XX%XX%XX`); 22 of them alone exceed 255 chars once encoded,
      // even though the raw name is only 44 UTF-16 code units long.
      final name = '😀' * 22;
      expect(
        () => JsonFileRegistry.validateName(name),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('JsonFileRegistry file name encoding', () {
    List<String> fileNames() =>
        tempDir.listSync().map((f) => p.basename(f.path)).toList();

    test('names matching the old strict pattern use a plain file name', () {
      registry.save(_Entry('my-app_1'));
      expect(fileNames(), equals(['my-app_1.json']));
    });

    test('names with Windows-unsafe characters round-trip', () {
      for (final name in [
        '192.168.240.112:5555',
        'a*b?c"d<e>f|g',
        'weird name',
      ]) {
        registry.save(_Entry(name));
        expect(registry.get(name)?.name, equals(name));
      }
    });

    test('does not create a file matching a Windows-reserved device name', () {
      for (final name in ['NUL', 'COM0', 'LPT0', 'COM1', 'LPT9']) {
        registry.save(_Entry(name));

        expect(fileNames(), isNot(contains('$name.json')));
        expect(registry.get(name)?.name, equals(name));
      }
    });

    test('a name ending in a dot round-trips via the .json suffix', () {
      // The on-disk file is "trailing..json" — a harmless double dot, since
      // the appended ".json" suffix means the actual file name never ends
      // in a dot regardless of what the encoded name looks like.
      registry.save(_Entry('trailing.'));

      expect(fileNames(), equals(['trailing..json']));
      expect(registry.get('trailing.')?.name, equals('trailing.'));
    });
  });

  group('JsonFileRegistry.save', () {
    test('concurrent saves of one entry from two isolates all succeed',
        () async {
      final baseDir = tempDir.path;
      void saveRepeatedly() {
        final registry = _Registry(baseDir);
        for (var i = 0; i < 500; i++) {
          registry.save(_Entry('app'));
        }
      }

      await Future.wait(
          [Isolate.run(saveRepeatedly), Isolate.run(saveRepeatedly)]);

      expect(registry.get('app')?.name, 'app');
    });

    test('a failed save leaves no temp file behind', () {
      Directory(p.join(tempDir.path, 'app.json', 'occupied'))
          .createSync(recursive: true);

      expect(
        () => registry.save(_Entry('app')),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        tempDir.listSync().map((f) => p.basename(f.path)),
        ['app.json'],
      );
    });
  });
}

class _Entry implements JsonFileEntry {
  _Entry(this.name);

  factory _Entry.fromJson(Map<String, dynamic> json) =>
      _Entry(json['name'] as String);

  @override
  final String name;

  @override
  Map<String, dynamic> toJson() => {'name': name};
}

class _Registry extends JsonFileRegistry<_Entry> {
  _Registry(String baseDir)
      : super(
            directoryName: 'test', fromJson: _Entry.fromJson, baseDir: baseDir);
}
