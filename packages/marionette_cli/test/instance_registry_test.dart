import 'dart:convert';
import 'dart:io';

import 'package:marionette_cli/src/instance_registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late InstanceRegistry registry;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('marionette_test_');
    registry = InstanceRegistry(baseDir: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('InstanceInfo', () {
    test('JSON roundtrip preserves all fields', () {
      final now = DateTime.utc(2026, 2, 26, 12, 30, 45);
      final info = InstanceInfo(
        name: 'my-app',
        uri: 'ws://127.0.0.1:8181/ws',
        registeredAt: now,
      );

      final json = info.toJson();
      final restored = InstanceInfo.fromJson(json);

      expect(restored.name, equals('my-app'));
      expect(restored.uri, equals('ws://127.0.0.1:8181/ws'));
      expect(restored.registeredAt, equals(now));
    });
  });

  group('InstanceRegistry.validateName', () {
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
          () => InstanceRegistry.validateName(name),
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
          () => InstanceRegistry.validateName(name),
          throwsA(isA<FormatException>()),
          reason: 'Expected "$name" to be invalid',
        );
      }
    });
  });

  group('InstanceRegistry file name encoding', () {
    List<String> fileNames() =>
        tempDir.listSync().map((f) => p.basename(f.path)).toList();

    test('names matching the old strict pattern use a plain file name',
        () async {
      await registry.register('my-app_1', 'ws://127.0.0.1:8181/ws');
      expect(fileNames(), equals(['my-app_1.json']));
    });

    test('names with Windows-unsafe characters round-trip', () async {
      for (final name in [
        '192.168.240.112:5555',
        'a*b?c"d<e>f|g',
        'weird name',
      ]) {
        await registry.register(name, 'ws://127.0.0.1:8181/ws');
        expect(registry.get(name)?.name, equals(name));
      }
    });

    test('does not create a file matching a Windows-reserved device name',
        () async {
      await registry.register('NUL', 'ws://127.0.0.1:8181/ws');

      expect(fileNames(), isNot(contains('NUL.json')));
      expect(registry.get('NUL')?.name, equals('NUL'));
    });

    test('does not create a file name ending in a dot', () async {
      await registry.register('trailing.', 'ws://127.0.0.1:8181/ws');

      expect(fileNames(), isNot(contains('trailing..json')));
      expect(registry.get('trailing.')?.name, equals('trailing.'));
    });
  });

  group('InstanceRegistry.register', () {
    test('register then get returns matching instance', () async {
      await registry.register('test-app', 'ws://127.0.0.1:8181/ws');

      final info = registry.get('test-app');
      expect(info, isNotNull);
      expect(info!.name, equals('test-app'));
      expect(info.uri, equals('ws://127.0.0.1:8181/ws'));
    });

    test('returns false for new instance', () async {
      final overwritten = await registry.register(
        'new-app',
        'ws://127.0.0.1:8181/ws',
      );
      expect(overwritten, isFalse);
    });

    test('returns true when overwriting existing instance', () async {
      await registry.register('my-app', 'ws://127.0.0.1:8181/ws');
      final overwritten = await registry.register(
        'my-app',
        'ws://127.0.0.1:9999/ws',
      );

      expect(overwritten, isTrue);

      final info = registry.get('my-app');
      expect(info!.uri, equals('ws://127.0.0.1:9999/ws'));
    });
  });

  group('InstanceRegistry.unregister', () {
    test('returns true when instance exists', () async {
      await registry.register('my-app', 'ws://127.0.0.1:8181/ws');
      final removed = registry.unregister('my-app');
      expect(removed, isTrue);
      expect(registry.get('my-app'), isNull);
    });

    test('returns false when instance not found', () {
      final removed = registry.unregister('nonexistent');
      expect(removed, isFalse);
    });
  });

  group('InstanceRegistry.get', () {
    test('returns null for unknown name', () {
      expect(registry.get('nonexistent'), isNull);
    });
  });

  group('InstanceRegistry.listAll', () {
    test('returns empty list for fresh directory', () {
      expect(registry.listAll(), isEmpty);
    });

    test('returns instances sorted alphabetically', () async {
      await registry.register('z-app', 'ws://127.0.0.1:1111/ws');
      await registry.register('a-app', 'ws://127.0.0.1:2222/ws');
      await registry.register('m-app', 'ws://127.0.0.1:3333/ws');

      final instances = registry.listAll();
      expect(instances.map((i) => i.name).toList(), [
        'a-app',
        'm-app',
        'z-app',
      ]);
    });

    test('skips corrupted JSON files', () async {
      await registry.register('good-app', 'ws://127.0.0.1:8181/ws');

      File(
        '${tempDir.path}/bad-app.json',
      ).writeAsStringSync('not valid json{{{');

      final instances = registry.listAll();
      expect(instances, hasLength(1));
      expect(instances.first.name, equals('good-app'));
    });

    test('skips .tmp files', () async {
      await registry.register('real-app', 'ws://127.0.0.1:8181/ws');

      final tmpContent = jsonEncode({
        'name': 'tmp-app',
        'uri': 'ws://127.0.0.1:9999/ws',
        'registeredAt': DateTime.now().toUtc().toIso8601String(),
      });
      File('${tempDir.path}/tmp-app.json.tmp').writeAsStringSync(tmpContent);

      final instances = registry.listAll();
      expect(instances, hasLength(1));
      expect(instances.first.name, equals('real-app'));
    });
  });
}
