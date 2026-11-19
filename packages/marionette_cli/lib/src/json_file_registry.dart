import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// An entry a [JsonFileRegistry] stores as one JSON file.
abstract interface class JsonFileEntry {
  String get name;

  Map<String, dynamic> toJson();
}

/// File-based registry of named entries.
///
/// Stores each entry in `~/.marionette/<directoryName>/<name>.json`, where
/// `<name>` is [JsonFileRegistry._encodeFileNameComponent]'s portable
/// encoding of the entry name (identical to the name itself for names made
/// up of letters, digits, `_`, `-`, and `.`).
abstract class JsonFileRegistry<T extends JsonFileEntry> {
  JsonFileRegistry({
    required String directoryName,
    required T Function(Map<String, dynamic> json) fromJson,
    String? baseDir,
  })  : _fromJson = fromJson,
        _baseDir = baseDir ??
            p.join(
              Platform.environment['HOME'] ??
                  Platform.environment['USERPROFILE'] ??
                  '.',
              '.marionette',
              directoryName,
            );

  final T Function(Map<String, dynamic> json) _fromJson;
  final String _baseDir;

  static final _random = Random();

  /// Characters that would let [name] escape [_baseDir] once it becomes part
  /// of a file path (`/`, `\`), or C0/DEL control characters. Control
  /// characters are rejected outright (rather than just NUL) because names
  /// are later printed verbatim: instance names by `register`, `list`,
  /// `doctor` and `unregister`, native session names by the `native-*`
  /// commands; allowing them would let a saved name forge output lines or
  /// inject terminal escape sequences. Everything else — including device
  /// identifiers like `192.168.1.1:5555` — is a valid name.
  static final _unsafeCharsPattern = RegExp(r'[/\\\x00-\x1f\x7f]');

  /// Characters that are safe to use verbatim in a filename on every
  /// platform, including Windows (which additionally forbids
  /// `< > : " | ? *`). Names made up only of these characters — the old,
  /// stricter [validateName] pattern plus `.` — encode to themselves, so
  /// existing on-disk `.json` files are unaffected.
  static final _fileNameSafeCharsPattern = RegExp(r'[a-zA-Z0-9_.-]');

  static const _windowsReservedBaseNames = {
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM0', 'COM1', 'COM2', 'COM3', 'COM4', //
    'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', //
    'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Most filesystems (ext4, APFS, NTFS) cap a single path component at 255
  /// bytes. [_encodeFileNameComponent] percent-encodes every byte outside
  /// [_fileNameSafeCharsPattern], so a name can end up far longer once
  /// encoded than it was as typed (one 4-byte UTF-8 character becomes
  /// `%XX%XX%XX%XX`, 12 bytes) — checking only the raw [name] length would
  /// still let a short, exotic name blow past the limit and crash
  /// `register` with an uncaught `FileSystemException`.
  static const _maxFileNameLength = 255;

  /// Validates that [name] is a safe entry name.
  static void validateName(String name) {
    if (name.isEmpty || _unsafeCharsPattern.hasMatch(name)) {
      throw FormatException(
        'Invalid name "$name". '
        'Names must not be empty and must not contain "/", "\\", or control '
        'characters.',
      );
    }

    final fileName = '${_encodeFileNameComponent(name)}.json';
    if (fileName.length > _maxFileNameLength) {
      throw FormatException(
        'Invalid name "$name". '
        'Its encoded file name is ${fileName.length} characters, exceeding '
        'the $_maxFileNameLength character limit most filesystems enforce '
        'for a single file name.',
      );
    }
  }

  /// Whether an entry named [name] exists.
  bool contains(String name) {
    validateName(name);
    return File(_filePath(name)).existsSync();
  }

  /// Saves [entry], replacing an entry with the same name.
  void save(T entry) {
    validateName(entry.name);

    final dir = Directory(_baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final json = const JsonEncoder.withIndent('  ').convert(entry.toJson());

    // Atomic write: write to a temp file of this save only (another process
    // may save the same entry at the same time), then rename it.
    final tmpFile = File(
      p.join(_baseDir, '.save-$pid-${_random.nextInt(1 << 32)}.tmp'),
    );
    try {
      tmpFile
        ..writeAsStringSync(json)
        ..renameSync(_filePath(entry.name));
    } on FileSystemException {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
      rethrow;
    }
  }

  /// Removes an entry. Returns true if it existed.
  bool remove(String name) {
    validateName(name);
    final file = File(_filePath(name));
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  /// Gets a single entry, or null if not found. Throws a [FormatException]
  /// that names the file when the entry is malformed.
  T? get(String name) {
    validateName(name);
    final file = File(_filePath(name));
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return _fromJson(json);
    } on FormatException catch (e) {
      throw _malformedEntry(file, e.message);
    } on TypeError catch (e) {
      throw _malformedEntry(file, '$e.');
    }
  }

  /// Lists all entries, sorted by name.
  List<T> listAll() {
    final dir = Directory(_baseDir);
    if (!dir.existsSync()) return [];

    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json') && !f.path.endsWith('.tmp'))
        .map((f) {
          try {
            final json =
                jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
            return _fromJson(json);
          } catch (_) {
            return null;
          }
        })
        .whereType<T>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static FormatException _malformedEntry(File file, String reason) =>
      FormatException(
        'Malformed entry ${file.path}: $reason Delete the file and try again.',
      );

  /// Encodes [name] into a filename component that is safe on every
  /// platform. Any character outside of [_fileNameSafeCharsPattern] is
  /// percent-encoded, and a leading character is percent-encoded too if the
  /// name would otherwise collide with a Windows-reserved device name (e.g.
  /// `NUL`).
  static String _encodeFileNameComponent(String name) {
    final buffer = StringBuffer();
    for (final rune in name.runes) {
      final char = String.fromCharCode(rune);
      if (_fileNameSafeCharsPattern.hasMatch(char)) {
        buffer.write(char);
      } else {
        for (final byte in utf8.encode(char)) {
          buffer.write(
              '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
        }
      }
    }

    var encoded = buffer.toString();

    final base = encoded.split('.').first.toUpperCase();
    if (_windowsReservedBaseNames.contains(base)) {
      encoded = _percentEncodeCharAt(encoded, 0);
    }

    return encoded;
  }

  static String _percentEncodeCharAt(String s, int index) {
    final code = s.codeUnitAt(index).toRadixString(16).padLeft(2, '0');
    return '${s.substring(0, index)}%${code.toUpperCase()}${s.substring(index + 1)}';
  }

  String _filePath(String name) =>
      p.join(_baseDir, '${_encodeFileNameComponent(name)}.json');
}
