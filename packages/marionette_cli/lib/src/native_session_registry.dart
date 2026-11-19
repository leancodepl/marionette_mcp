import 'package:marionette_cli/src/json_file_registry.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';

/// A native automation session kept between CLI commands.
///
/// The device-side server runs detached from the CLI and every command
/// attaches to it.
class NativeSessionInfo implements JsonFileEntry {
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
      platform: NativePlatform.values.asNameMap()[json['platform']] ??
          (throw FormatException(
            'Unknown native platform "${json['platform']}".',
          )),
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

  @override
  final String name;

  final NativePlatform platform;

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

  @override
  Map<String, dynamic> toJson() => {
        'name': name,
        'platform': platform.name,
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

  /// Whether a connect to [platform] with [serial] and [udid] (null: any
  /// device) asks for the device this session drives.
  bool targets(NativePlatform platform, {String? serial, String? udid}) =>
      this.platform == platform &&
      (serial == null || serial == this.serial) &&
      (udid == null || udid == this.udid);
}

/// File-based registry for named native sessions, stored in
/// `~/.marionette/native/`.
class NativeSessionRegistry extends JsonFileRegistry<NativeSessionInfo> {
  NativeSessionRegistry({super.baseDir})
      : super(directoryName: 'native', fromJson: NativeSessionInfo.fromJson);
}
