import 'dart:io';

import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late NativeSessionRegistry registry;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('marionette_native_test_');
    registry = NativeSessionRegistry(baseDir: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  NativeSessionInfo session(String name, {String? sessionId}) =>
      NativeSessionInfo(
        name: name,
        platform: NativePlatform.android,
        baseUrl: 'http://127.0.0.1:8200',
        createdAt: DateTime.utc(2026, 10, 20, 12),
        serial: 'emulator-5554',
        port: 8200,
        sessionId: sessionId,
        pid: 4242,
        startedServer: true,
      );

  test('JSON roundtrip preserves all fields', () {
    final info = session('default', sessionId: 'sess-1');

    final restored = NativeSessionInfo.fromJson(info.toJson());

    expect(restored.toJson(), info.toJson());
    expect(restored.device, 'emulator-5554');
  });

  test('save, get, list and remove', () {
    registry
      ..save(session('pixel'))
      ..save(session('default', sessionId: 'sess-1'));

    expect(registry.get('default')!.sessionId, 'sess-1');
    expect(registry.listAll().map((s) => s.name), ['default', 'pixel']);
    expect(registry.remove('pixel'), isTrue);
    expect(registry.remove('pixel'), isFalse);
    expect(registry.get('pixel'), isNull);
  });

  test('save replaces the entry and leaves no temporary file', () {
    registry
      ..save(session('default', sessionId: 'old'))
      ..save(session('default', sessionId: 'new'));

    expect(registry.get('default')!.sessionId, 'new');
    expect(
      tempDir.listSync().map((f) => p.basename(f.path)),
      ['default.json'],
    );
  });

  test('encodes the file name like an instance name and round-trips', () {
    registry.save(session('a b', sessionId: 'sess-1'));

    expect(
      tempDir.listSync().map((f) => p.basename(f.path)),
      ['a%20b.json'],
    );
    expect(registry.get('a b')!.sessionId, 'sess-1');
    expect(registry.listAll().map((s) => s.name), ['a b']);
    expect(registry.remove('a b'), isTrue);
    expect(tempDir.listSync(), isEmpty);
  });

  test('an entry with an unknown platform names its file to delete', () {
    registry.save(session('default'));
    final file = File('${tempDir.path}/default.json');
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst('"android"', '"Android"'),
    );

    expect(
      () => registry.get('default'),
      throwsA(
        isA<FormatException>()
            .having((e) => e.message, 'message', contains(file.path)),
      ),
    );
  });

  test('an entry with a field of the wrong type names its file to delete', () {
    registry.save(session('default'));
    final file = File('${tempDir.path}/default.json');
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst('"port": 8200', '"port": "8200"'),
    );

    expect(
      () => registry.get('default'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains(file.path), contains('Delete the file')),
        ),
      ),
    );
  });

  test('rejects unsafe names', () {
    expect(() => registry.get('../x'), throwsFormatException);
  });
}
