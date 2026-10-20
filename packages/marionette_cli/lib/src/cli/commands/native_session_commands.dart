import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/native_command.dart';
import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_service_context.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';

/// Starts the device-side server detached from the CLI and records the
/// session, so later `native-*` commands attach to it
/// (docs/native-lane-decisions.md#d4).
class NativeConnectCommand extends Command<int> {
  NativeConnectCommand(this._registry) {
    argParser
      ..addOption(
        'platform',
        allowed: [for (final p in NativePlatform.values) p.name],
        mandatory: true,
      )
      ..addOption('serial', help: 'Android device serial (adb devices).')
      ..addOption('udid', help: 'iOS Simulator UDID (xcrun simctl list).');
  }

  final NativeSessionRegistry _registry;

  @override
  String get name => 'native-connect';

  @override
  String get description =>
      'Start a native automation session (UIAutomator2 on Android, '
      'WebDriverAgent on an iOS Simulator) that later native-* commands use. '
      'The server keeps running until native-disconnect.';

  @override
  Future<int> run() async {
    final name = nativeSessionName(globalResults);
    final platform =
        NativePlatform.tryParse(argResults!['platform'] as String)!;
    final serial = argResults!['serial'] as String?;
    final udid = argResults!['udid'] as String?;

    final existing = _registry.get(name);
    if (existing != null &&
        existing.platform == platform.name &&
        (serial == null || serial == existing.serial) &&
        (udid == null || udid == existing.udid) &&
        await _isRunning(existing.baseUrl)) {
      stdout.writeln(
        'Native session "$name" is already connected '
        '(${existing.platform}, ${existing.device}).',
      );
      return 0;
    }

    stdout.writeln(
      'Starting the native server (${platform.name}); the first start can '
      'take a minute...',
    );
    final WebDriverNativeConnector connector;
    final NativeSessionInfo info;
    // Stops a server this command started when the session cannot be opened.
    Future<void> Function()? stopStarted;
    try {
      switch (platform) {
        case NativePlatform.android:
          final bootstrap = AndroidBootstrap(serial: serial, detached: true);
          final baseUrl = await bootstrap.ensureServerReady();
          if (bootstrap.startedServer) {
            stopStarted = () => _stopAndroidServer(
                  bootstrap.adb,
                  bootstrap.localPort,
                  bootstrap.detachedPid,
                );
          }
          final resolvedSerial = await bootstrap.adb.resolveSerial();
          connector = await AndroidNativeConnector.connect(
            serial: resolvedSerial,
            bootstrap: bootstrap,
            adb: bootstrap.adb,
          );
          info = NativeSessionInfo(
            name: name,
            platform: platform.name,
            baseUrl: baseUrl.toString(),
            createdAt: DateTime.now(),
            serial: resolvedSerial,
            port: bootstrap.localPort,
            pid: bootstrap.detachedPid,
            startedServer: bootstrap.startedServer,
          );
        case NativePlatform.ios:
          final bootstrap = IosBootstrap(udid: udid, detached: true);
          final baseUrl = await bootstrap.ensureServerReady();
          if (bootstrap.detachedPid case final pid?) {
            stopStarted = () => _stopDetached(pid, 'xcodebuild', baseUrl);
          }
          connector = await IosNativeConnector.connect(
            udid: bootstrap.resolvedUdid ?? udid,
            bootstrap: bootstrap,
          );
          info = NativeSessionInfo(
            name: name,
            platform: platform.name,
            baseUrl: baseUrl.toString(),
            createdAt: DateTime.now(),
            udid: bootstrap.resolvedUdid ?? udid,
            pid: bootstrap.detachedPid,
            startedServer: bootstrap.detachedPid != null,
          );
      }
    } catch (e) {
      await stopStarted?.call();
      stderr.writeln('Failed to connect native session "$name": $e');
      return 1;
    }

    // The app in front becomes the default for device shortcuts
    // (docs/native-lane-decisions.md#d7).
    final context = NativeServiceContext()
      ..connector = connector
      ..platform = platform;
    await context.observeForegroundAppIfUnknown();
    info
      ..sessionId = connector.sessionId
      ..defaultAppId = context.defaultAppId;
    _registry.save(info);
    connector.release();

    stdout.writeln(
      'Connected native session "$name" (${info.platform}, ${info.device}) '
      'at ${info.baseUrl}'
      '${info.startedServer ? '' : ' — reusing a server that was already running'}.',
    );
    if (!info.startedServer && platform == NativePlatform.android) {
      // UIAutomator2 has one session per device (D10): the two clients take
      // it from each other.
      stdout.writeln(
        'Warning: another process (e.g. an MCP server) uses UIAutomator2 on '
        'this device. It has one session per device — while both are used, '
        'each takes the session from the other and that process may fail. '
        'Use one client per Android device at a time.',
      );
    }
    return 0;
  }
}

/// Ends a native session: deletes the WebDriver session, stops the server
/// if `native-connect` started it, and removes the entry.
class NativeDisconnectCommand extends Command<int> {
  NativeDisconnectCommand(this._registry);

  final NativeSessionRegistry _registry;

  @override
  String get name => 'native-disconnect';

  @override
  String get description =>
      'End a native session and stop the server native-connect started.';

  @override
  Future<int> run() async {
    final name = nativeSessionName(globalResults);
    final info = _registry.get(name);
    if (info == null) {
      stderr.writeln(
        'No native session "$name". '
        'Use "marionette native-sessions" to list them.',
      );
      return 1;
    }

    // UIAutomator2 stops itself when its session is deleted: on a server
    // another process started, the session is left to that process
    // (docs/native-lane-decisions.md#d10).
    final sessionId = info.sessionId;
    if (sessionId != null && info.startedServer) {
      final client = WebDriverClient(info.baseUrl);
      try {
        await client.deleteSession(sessionId);
      } catch (_) {
        // The server may already be gone.
      } finally {
        client.close();
      }
    }

    var note = '';
    if (!info.startedServer) {
      note = ' The server was already running before native-connect and is '
          'left running.';
    } else if (info.platform == NativePlatform.android.name) {
      await _stopAndroidServer(
        AdbClient(serial: info.serial),
        info.port,
        info.pid,
      );
    } else if (info.pid case final pid?) {
      await _stopDetached(pid, 'xcodebuild', Uri.parse(info.baseUrl));
    }

    _registry.remove(name);
    stdout.writeln('Disconnected native session "$name".$note');
    return 0;
  }
}

/// Stops UIAutomator2 on the device, removes the forward of [port] and ends
/// the detached `adb` process [pid] that held the instrumentation.
Future<void> _stopAndroidServer(AdbClient adb, int? port, int? pid) async {
  await AndroidBootstrap.stopServer(adb, port: port);
  if (pid != null) await _stopDetached(pid, 'am instrument', null);
}

/// Ends detached process [pid] if it still runs [command] (pids are reused):
/// SIGTERM, then SIGKILL when [baseUrl] keeps answering (or after 5 s).
Future<void> _stopDetached(int pid, String command, Uri? baseUrl) async {
  final ps = await Process.run('ps', ['-p', '$pid', '-o', 'command=']);
  if (!(ps.stdout as String).contains(command)) return;
  Process.killPid(pid);
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final alive = await Process.run('ps', ['-p', '$pid']);
    if (alive.exitCode != 0) return;
    if (baseUrl != null && !await _isRunning(baseUrl.toString())) return;
  }
  Process.killPid(pid, ProcessSignal.sigkill);
}

/// Lists native sessions and whether their servers still run.
class NativeSessionsCommand extends Command<int> {
  NativeSessionsCommand(this._registry);

  final NativeSessionRegistry _registry;

  @override
  String get name => 'native-sessions';

  @override
  String get description =>
      'List native sessions and whether their servers are running.';

  @override
  Future<int> run() async {
    final sessions = _registry.listAll();
    if (sessions.isEmpty) {
      stdout.writeln('No native sessions. Start one with native-connect.');
      return 0;
    }
    for (final info in sessions) {
      final running = await _isRunning(info.baseUrl);
      stdout.writeln(
        '${info.name}\t${info.platform}\t${info.device}\t${info.baseUrl}\t'
        '${running ? 'running' : 'not running'}',
      );
    }
    return 0;
  }
}

Future<bool> _isRunning(String baseUrl) async {
  final client = WebDriverClient(baseUrl);
  try {
    return await client.status().timeout(const Duration(seconds: 3));
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}
