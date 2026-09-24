import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Metadata for a registered Flutter app instance.
class InstanceInfo {
  InstanceInfo({
    required this.name,
    required this.uri,
    required this.registeredAt,
  });

  factory InstanceInfo.fromJson(Map<String, dynamic> json) {
    return InstanceInfo(
      name: json['name'] as String,
      uri: json['uri'] as String,
      registeredAt: DateTime.parse(json['registeredAt'] as String),
    );
  }

  final String name;
  final String uri;
  final DateTime registeredAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'uri': uri,
        'registeredAt': registeredAt.toUtc().toIso8601String(),
      };
}

/// File-based registry for named Flutter app instances.
///
/// Stores instance metadata in `~/.marionette/instances/<name>.json`, where
/// `<name>` is [InstanceRegistry._encodeFileNameComponent]'s portable
/// encoding of the instance name (identical to the name itself for names
/// made up of letters, digits, `_`, `-`, and `.`).
class InstanceRegistry {
  InstanceRegistry({String? baseDir})
      : _baseDir = baseDir ??
            p.join(
              Platform.environment['HOME'] ??
                  Platform.environment['USERPROFILE'] ??
                  '.',
              '.marionette',
              'instances',
            );

  final String _baseDir;

  /// Characters that would let [name] escape [_baseDir] once it becomes part
  /// of a file path (`/`, `\`), or C0/DEL control characters. Control
  /// characters are rejected outright (rather than just NUL) because
  /// instance names are later printed verbatim by `register`, `list`,
  /// `doctor`, and `unregister`; allowing them would let a registered name
  /// forge output lines or inject terminal escape sequences. Everything
  /// else — including device identifiers like `192.168.1.1:5555` — is a
  /// valid instance name.
  static final _unsafeCharsPattern = RegExp(r'[/\\\x00-\x1f\x7f]');

  /// Characters that are safe to use verbatim in a filename on every
  /// platform, including Windows (which additionally forbids
  /// `< > : " | ? *`). This is intentionally the same set the old, stricter
  /// [validateName] pattern allowed, so names that were already valid
  /// (and their on-disk `.json` files) are unaffected.
  static final _fileNameSafeCharsPattern = RegExp(r'[a-zA-Z0-9_.-]');

  static const _windowsReservedBaseNames = {
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Validates that [name] is a safe instance name.
  static void validateName(String name) {
    if (name.isEmpty || _unsafeCharsPattern.hasMatch(name)) {
      throw FormatException(
        'Invalid instance name "$name". '
        'Names must not be empty and must not contain "/", "\\", or control '
        'characters.',
      );
    }
  }

  /// Encodes [name] into a filename component that is safe on every
  /// platform. Any character outside of [_fileNameSafeCharsPattern] is
  /// percent-encoded, and a leading character is percent-encoded too if the
  /// name would otherwise collide with a Windows-reserved device name (e.g.
  /// `NUL`) or end in a dot, which Windows also forbids.
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
    if (encoded.endsWith('.')) {
      encoded = _percentEncodeCharAt(encoded, encoded.length - 1);
    }

    return encoded;
  }

  static String _percentEncodeCharAt(String s, int index) {
    final code = s.codeUnitAt(index).toRadixString(16).padLeft(2, '0');
    return '${s.substring(0, index)}%${code.toUpperCase()}${s.substring(index + 1)}';
  }

  String _filePath(String name) =>
      p.join(_baseDir, '${_encodeFileNameComponent(name)}.json');

  /// Registers an instance. Overwrites if already exists.
  ///
  /// Returns true if an existing instance was overwritten.
  Future<bool> register(String name, String uri) async {
    validateName(name);

    final dir = Directory(_baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final existed = File(_filePath(name)).existsSync();

    final info = InstanceInfo(
      name: name,
      uri: uri,
      registeredAt: DateTime.now(),
    );

    final json = const JsonEncoder.withIndent('  ').convert(info.toJson());

    // Atomic write: write to tmp, then rename
    final tmpFile = File('${_filePath(name)}.tmp');
    tmpFile.writeAsStringSync(json);
    tmpFile.renameSync(_filePath(name));

    return existed;
  }

  /// Unregisters an instance. Returns true if it existed.
  bool unregister(String name) {
    validateName(name);
    final file = File(_filePath(name));
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  /// Gets info for a single instance, or null if not found.
  InstanceInfo? get(String name) {
    validateName(name);
    final file = File(_filePath(name));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return InstanceInfo.fromJson(json);
  }

  /// Lists all registered instances.
  List<InstanceInfo> listAll() {
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
            return InstanceInfo.fromJson(json);
          } catch (_) {
            return null;
          }
        })
        .whereType<InstanceInfo>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}
