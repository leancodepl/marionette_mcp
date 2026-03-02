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
/// Stores instance metadata in `~/.marionette/instances/<name>.json`.
class InstanceRegistry {
  InstanceRegistry({String? baseDir})
    : _baseDir =
          baseDir ??
          p.join(
            Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                '.',
            '.marionette',
            'instances',
          );

  final String _baseDir;

  static final _namePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

  /// Validates that [name] is a safe instance name.
  static void validateName(String name) {
    if (!_namePattern.hasMatch(name)) {
      throw FormatException(
        'Invalid instance name "$name". '
        'Names must match [a-zA-Z0-9_-]+.',
      );
    }
  }

  String _filePath(String name) => p.join(_baseDir, '$name.json');

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
