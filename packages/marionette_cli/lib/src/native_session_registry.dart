import 'dart:convert';
import 'dart:io';

import 'package:marionette_cli/src/instance_registry.dart';
import 'package:path/path.dart' as p;

/// A native automation session kept between CLI commands.
///
/// The device-side server runs detached from the CLI and every command
/// attaches to it (docs/native-lane-decisions.md#d4).
class NativeSessionInfo {
  NativeSessionInfo({
    required this.name,
    required this.platform,
    required this.baseUrl,
    required this.createdAt,
    this.serial,
    this.udid,
    this.port,
    this.sessionId,
    this.pid,
    this.startedServer = false,
  });

  factory NativeSessionInfo.fromJson(Map<String, dynamic> json) {
    return NativeSessionInfo(
      name: json['name'] as String,
      platform: json['platform'] as String,
      baseUrl: json['baseUrl'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      serial: json['serial'] as String?,
      udid: json['udid'] as String?,
      port: json['port'] as int?,
      sessionId: json['sessionId'] as String?,
      pid: json['pid'] as int?,
      startedServer: json['startedServer'] as bool? ?? false,
    );
  }

  final String name;

  /// `android` or `ios`.
  final String platform;

  /// Local WebDriver URL of the device-side server.
  final String baseUrl;
  final DateTime createdAt;

  /// Android device serial.
  final String? serial;

  /// iOS Simulator UDID.
  final String? udid;

  /// Local port forwarded to UIAutomator2 (Android).
  final int? port;

  /// WebDriver session reused by the next command; replaced when the server
  /// no longer has it.
  String? sessionId;

  /// Pid of the detached process holding the server: `adb shell am
  /// instrument -w` (Android) or `xcodebuild` running WebDriverAgent (iOS).
  final int? pid;

  /// Whether `native-connect` started the server, so `native-disconnect`
  /// stops it. A server that was already running is left alone.
  final bool startedServer;

  Map<String, dynamic> toJson() => {
        'name': name,
        'platform': platform,
        'baseUrl': baseUrl,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (serial != null) 'serial': serial,
        if (udid != null) 'udid': udid,
        if (port != null) 'port': port,
        if (sessionId != null) 'sessionId': sessionId,
        if (pid != null) 'pid': pid,
        'startedServer': startedServer,
      };

  /// Device the session drives, for messages.
  String get device => serial ?? udid ?? 'default device';
}

/// File-based registry for named native sessions.
///
/// Stores session metadata in `~/.marionette/native/<name>.json`.
class NativeSessionRegistry {
  NativeSessionRegistry({String? baseDir})
      : _baseDir = baseDir ??
            p.join(
              Platform.environment['HOME'] ??
                  Platform.environment['USERPROFILE'] ??
                  '.',
              '.marionette',
              'native',
            );

  final String _baseDir;

  String _filePath(String name) => p.join(_baseDir, '$name.json');

  /// Saves [info], replacing an entry with the same name.
  void save(NativeSessionInfo info) {
    InstanceRegistry.validateName(info.name);

    final dir = Directory(_baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final json = const JsonEncoder.withIndent('  ').convert(info.toJson());

    // Atomic write: write to tmp, then rename
    final tmpFile = File('${_filePath(info.name)}.tmp');
    tmpFile.writeAsStringSync(json);
    tmpFile.renameSync(_filePath(info.name));
  }

  /// Removes a session. Returns true if it existed.
  bool remove(String name) {
    InstanceRegistry.validateName(name);
    final file = File(_filePath(name));
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  /// Gets a single session, or null if not found.
  NativeSessionInfo? get(String name) {
    InstanceRegistry.validateName(name);
    final file = File(_filePath(name));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return NativeSessionInfo.fromJson(json);
  }

  /// Lists all sessions.
  List<NativeSessionInfo> listAll() {
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
            return NativeSessionInfo.fromJson(json);
          } catch (_) {
            return null;
          }
        })
        .whereType<NativeSessionInfo>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}
