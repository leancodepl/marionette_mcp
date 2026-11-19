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
import 'package:marionette_mcp/src/native_service/poll.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';

/// Starts the device-side server detached from the CLI and records the
/// session, so later `native-*` commands attach to it.
class NativeConnectCommand extends Command<int> {
  NativeConnectCommand(this._registry) {
    argParser
      ..addOption(
        'platform',
        help: 'Target platform: android (UIAutomator2) or ios '
            '(WebDriverAgent on a Simulator).',
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
    if (existing != null) {
      final sameDevice = existing.targets(platform, serial: serial, udid: udid);
      if (!sameDevice && existing.startedServer) {
        stderr.writeln(
          'Native session "$name" runs a server it started on '
          '${existing.platform.name} ${existing.device}.\n'
          'Hint: Run "${nativeCommandLine(name, 'native-disconnect')}" '
          'first, or pass another --native-device.',
        );
        return 1;
      }
      if (sameDevice) {
        if (await _isRunning(existing.baseUrl)) {
          stdout.writeln(
            'Native session "$name" is already connected '
            '(${existing.platform.name}, ${existing.device}).',
          );
          return 0;
        }
        // The new entry replaces the recorded pid, so nothing could stop the
        // old server later.
        if (existing.startedServer) await _stopStartedServer(existing);
      }
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
            platform: platform,
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
            platform: platform,
            baseUrl: baseUrl.toString(),
            createdAt: DateTime.now(),
            udid: bootstrap.resolvedUdid ?? udid,
            pid: bootstrap.detachedPid,
            startedServer: bootstrap.detachedPid != null,
          );
      }
    } catch (e) {
      await stopStarted?.call();
      stderr.writeln(
        cliText(
          'Failed to connect native session "$name": $e',
          runner!.commands.keys.toSet(),
        ),
      );
      return 1;
    }

    info.sessionId = connector.sessionId;
    _registry.save(info);
    connector.release();

    stdout.writeln(
      'Connected native session "$name" (${platform.name}, ${info.device}) '
      'at ${info.baseUrl}'
      '${info.startedServer ? '' : ' — reusing a server that was already running'}.',
    );
    if (oneClientWarning(info) case final warning?) stdout.writeln(warning);
    return 0;
  }
}

/// Warning for a session on a server that another process started:
/// UIAutomator2 and WebDriverAgent keep one session per device, so two
/// clients take it from each other.
String? oneClientWarning(NativeSessionInfo info) {
  if (info.startedServer) return null;
  return 'Warning: another process (e.g. an MCP server) uses the native '
      'server on this device. It has one session per device — while both '
      'are used, each takes the session from the other, and the MCP server '
      'then needs native_connect again. Use one client per device at a time.';
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
    // another process started, the session is left to that process.
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
    if (info.startedServer) {
      await _stopStartedServer(info);
    } else {
      note = ' The server was already running before native-connect and is '
          'left running.';
    }

    _registry.remove(name);
    stdout.writeln('Disconnected native session "$name".$note');
    return 0;
  }
}

/// Stops the server `native-connect` started for [info].
Future<void> _stopStartedServer(NativeSessionInfo info) async {
  switch (info.platform) {
    case NativePlatform.android:
      await _stopAndroidServer(
        AdbClient(serial: info.serial),
        info.port,
        info.pid,
      );
    case NativePlatform.ios:
      if (info.pid case final pid?) {
        await _stopDetached(pid, 'xcodebuild', Uri.parse(info.baseUrl));
      }
  }
}

/// Stops UIAutomator2 on the device, removes the forward of [port] and ends
/// the detached `adb` process [pid] that held the instrumentation.
Future<void> _stopAndroidServer(AdbClient adb, int? port, int? pid) async {
  await AndroidBootstrap.stopServer(adb, port: port);
  if (pid != null) await _stopDetached(pid, 'am instrument', null);
}

/// How often and how long [_stopDetached] checks that a process ended after
/// SIGTERM (the last check at 5 s).
const _stopChecks = 21;
const _stopCheckInterval = Duration(milliseconds: 250);

/// Ends detached process [pid] if it still runs [command] (pids are reused):
/// SIGTERM, then SIGKILL when [baseUrl] keeps answering (or after 5 s).
Future<void> _stopDetached(int pid, String command, Uri? baseUrl) async {
  final ps = await Process.run('ps', ['-p', '$pid', '-o', 'command=']);
  if (!(ps.stdout as String).contains(command)) return;
  Process.killPid(pid);
  final stopped = await pollUntil(
    () async {
      final alive = await Process.run('ps', ['-p', '$pid']);
      if (alive.exitCode != 0) return true;
      return baseUrl != null && !await _isRunning(baseUrl.toString());
    },
    attempts: _stopChecks,
    interval: _stopCheckInterval,
  );
  if (!stopped) Process.killPid(pid, ProcessSignal.sigkill);
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
        '${info.name}\t${info.platform.name}\t${info.device}\t'
        '${info.baseUrl}\t'
        '${running ? 'running' : 'not running'}',
      );
    }
    return 0;
  }
}

/// Longest [_isRunning] waits for `/status`. Shorter than
/// [webDriverShortTimeout]: `native-sessions` checks every session in turn.
const _isRunningTimeout = Duration(seconds: 3);

/// Whether a server answers at [baseUrl]. A URL the client cannot call (the
/// registry file can be edited by hand) counts as not running, so
/// `native-connect` can replace the entry and `native-disconnect` remove it.
Future<bool> _isRunning(String baseUrl) async {
  final uri = Uri.tryParse(baseUrl);
  final callable = uri != null &&
      (uri.isScheme('http') || uri.isScheme('https')) &&
      uri.host.isNotEmpty;
  if (!callable) return false;
  final client = WebDriverClient(baseUrl, shortTimeout: _isRunningTimeout);
  try {
    return await client.status();
  } finally {
    client.close();
  }
}
