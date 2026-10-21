import 'dart:io';

import 'package:marionette_cli/src/native_session_registry.dart';
import 'package:marionette_mcp/src/native_service/android_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/ios_bootstrap.dart';
import 'package:marionette_mcp/src/native_service/process.dart';
import 'package:marionette_mcp/src/native_service/simctl_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// Outcome of one native-lane check.
enum DoctorStatus {
  /// Works.
  ok,

  /// Not set up, which matters only for the platform it concerns.
  note,

  /// Broken; [DoctorFinding.fix] says how to repair it.
  problem,
}

/// One line of the native-lane doctor report.
typedef DoctorFinding = ({DoctorStatus status, String message, String? fix});

/// Checks the native lane's prerequisites and leftovers: adb and devices,
/// the UIAutomator2 cache, Xcode, booted simulators, the WebDriverAgent
/// build, detached servers nobody owns and the CLI's native sessions
/// (docs/native-lane-decisions.md#d4).
class NativeDoctor {
  NativeDoctor({
    required NativeSessionRegistry registry,
    ProcessRunner? processRunner,
    Map<String, String>? environment,
    bool? isMacOS,
    Directory? uia2CacheDir,
    Directory? wdaCacheDir,
    Future<bool> Function(String baseUrl)? isServerRunning,
    Future<bool> Function(int port)? isPortFree,
  })  : _registry = registry,
        _run = processRunner ?? Process.run,
        _environment = environment ?? Platform.environment,
        _isMacOS = isMacOS ?? Platform.isMacOS,
        _uia2CacheDir = uia2CacheDir ?? AndroidBootstrap.defaultCacheDir,
        _wdaCacheDir = wdaCacheDir ?? defaultWdaCacheDir,
        _isServerRunning = isServerRunning ?? _serverAnswers,
        _isPortFree = isPortFree ?? canBindLoopbackPort;

  final NativeSessionRegistry _registry;
  final ProcessRunner _run;
  final Map<String, String> _environment;
  final bool _isMacOS;
  final Directory _uia2CacheDir;
  final Directory _wdaCacheDir;
  final Future<bool> Function(String baseUrl) _isServerRunning;
  final Future<bool> Function(int port) _isPortFree;

  /// Port WebDriverAgent listens on; the UIAutomator2 port is chosen free
  /// automatically (docs/native-lane-decisions.md#d10).
  static const _wdaPort = 8100;

  /// Runs every check and returns the findings in report order.
  Future<List<DoctorFinding>> check() async => [
        ...await _checkAdb(),
        ...await _checkUia2Apks(),
        if (_isMacOS) ...[
          ...await _checkSimulators(),
          _checkWda(),
          ...await _checkWdaPort(),
        ],
        ...await _checkDetachedServers(),
        ...await _checkSessions(),
      ];

  Future<List<DoctorFinding>> _checkAdb() async {
    final ProcessResult version;
    try {
      version = await _run('adb', const ['version']);
    } on ProcessException {
      return [
        (
          status: DoctorStatus.note,
          message: 'adb not found (needed for Android only).',
          fix: 'Install Android SDK platform-tools and add them to PATH.',
        ),
      ];
    }
    if (version.exitCode != 0) {
      return [
        (
          status: DoctorStatus.problem,
          message: 'adb version failed: ${processMessage(version)}',
          fix: 'Reinstall Android SDK platform-tools.',
        ),
      ];
    }
    final findings = <DoctorFinding>[
      (
        status: DoctorStatus.ok,
        message: processStdout(version).split('\n').first.trim(),
        fix: null,
      ),
    ];
    final devices = await _run('adb', const ['devices']);
    final lines = processStdout(devices)
        .split('\n')
        .skip(1)
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where((parts) => parts.length >= 2);
    if (lines.isEmpty) {
      findings.add((
        status: DoctorStatus.note,
        message: 'No Android device connected.',
        fix: 'Start an emulator or connect a phone with USB debugging on.',
      ));
    }
    for (final [serial, state, ...] in lines) {
      findings.add(switch (state) {
        'device' => (
            status: DoctorStatus.ok,
            message: 'Android device $serial',
            fix: null,
          ),
        'unauthorized' => (
            status: DoctorStatus.problem,
            message: 'Android device $serial is unauthorized.',
            fix: 'Accept the USB debugging prompt on the device.',
          ),
        _ => (
            status: DoctorStatus.problem,
            message: 'Android device $serial is $state.',
            fix: 'Run "adb reconnect", or restart the device / emulator.',
          ),
      });
    }
    return findings;
  }

  /// The UIAutomator2 APKs: overridden by environment variables, or the
  /// pinned version in the cache with its checksum.
  Future<List<DoctorFinding>> _checkUia2Apks() async {
    const overrides = [
      'MARIONETTE_UIA2_SERVER_APK',
      'MARIONETTE_UIA2_TEST_APK',
    ];
    final findings = <DoctorFinding>[];
    for (final key in overrides) {
      final path = _environment[key];
      if (path == null || path.isEmpty) continue;
      findings.add(
        File(path).existsSync()
            ? (status: DoctorStatus.ok, message: '$key: $path', fix: null)
            : (
                status: DoctorStatus.problem,
                message: '$key points to a missing file: $path',
                fix: 'Fix or unset $key.',
              ),
      );
    }
    if (findings.length == overrides.length) return findings;

    final version = AndroidBootstrap.uia2Version;
    final states = [
      for (final name in AndroidBootstrap.apkFileNames)
        await AndroidBootstrap.cachedApkValid(_uia2CacheDir, name),
    ];
    if (states.every((valid) => valid ?? false)) {
      findings.add((
        status: DoctorStatus.ok,
        message: 'UIAutomator2 $version cached and verified in '
            '${_uia2CacheDir.path}',
        fix: null,
      ));
    } else if (states.contains(false)) {
      findings.add((
        status: DoctorStatus.note,
        message: 'A cached UIAutomator2 APK does not match its pinned '
            'checksum; the next Android native-connect downloads it again '
            '(needs network).',
        fix: null,
      ));
    } else {
      findings.add((
        status: DoctorStatus.note,
        message: 'UIAutomator2 $version is not cached yet; the first Android '
            'native-connect downloads it.',
        fix: null,
      ));
    }
    return findings;
  }

  Future<List<DoctorFinding>> _checkSimulators() async {
    final List<String> booted;
    try {
      booted = await SimctlClient(processRunner: _run).listBootedUdids();
    } catch (_) {
      return [
        (
          status: DoctorStatus.note,
          message: 'xcrun simctl is not available (needed for iOS only).',
          fix: 'Install Xcode and run "xcode-select --install".',
        ),
      ];
    }
    if (booted.isEmpty) {
      return [
        (
          status: DoctorStatus.note,
          message: 'No iOS Simulator is booted.',
          fix: 'Run "open -a Simulator" or "xcrun simctl boot <udid>".',
        ),
      ];
    }
    return [
      for (final udid in booted)
        (status: DoctorStatus.ok, message: 'iOS Simulator $udid', fix: null),
    ];
  }

  DoctorFinding _checkWda() {
    // Same precedence as IosBootstrap: the .xctestrun first, then a runner
    // bundle or products directory.
    for (final key in const [
      'MARIONETTE_WDA_XCTESTRUN',
      'MARIONETTE_WDA_BUNDLE',
      'MARIONETTE_WDA_PATH',
    ]) {
      final path = _environment[key];
      if (path == null || path.isEmpty) continue;
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound
          ? (
              status: DoctorStatus.ok,
              message: 'WebDriverAgent ($key): $path',
              fix: null
            )
          : (
              status: DoctorStatus.problem,
              message: '$key points to a missing path: $path',
              fix: 'Build WebDriverAgent again or fix the variable.',
            );
    }
    final built = _wdaCacheDir.existsSync() &&
        _wdaCacheDir
            .listSync(recursive: true, followLinks: false)
            .any((entity) => entity.path.endsWith('.xctestrun'));
    return built
        ? (
            status: DoctorStatus.ok,
            message: 'WebDriverAgent built in ${_wdaCacheDir.path}',
            fix: null,
          )
        : (
            status: DoctorStatus.note,
            message: 'No prebuilt WebDriverAgent (needed for iOS only).',
            fix: 'Build it once with "xcodebuild build-for-testing" into '
                '${_wdaCacheDir.path} — see the native lane docs.',
          );
  }

  /// Port 8100 taken by something that is not WebDriverAgent blocks every
  /// iOS session.
  Future<List<DoctorFinding>> _checkWdaPort() async {
    if (await _isPortFree(_wdaPort)) return const [];
    if (await _isServerRunning('http://127.0.0.1:$_wdaPort')) return const [];
    return [
      (
        status: DoctorStatus.problem,
        message: 'Port $_wdaPort, which WebDriverAgent needs, is used by '
            'another program.',
        fix: 'Find it with "lsof -nP -iTCP:$_wdaPort -sTCP:LISTEN" and stop '
            'it.',
      ),
    ];
  }

  /// Device servers held by host processes: owned by a native session,
  /// held by another live process (e.g. an MCP server), or orphaned.
  Future<List<DoctorFinding>> _checkDetachedServers() async {
    final ProcessResult ps;
    try {
      ps = await _run('ps', const ['-axo', 'pid=,ppid=,command=']);
    } catch (_) {
      return const [];
    }
    final sessionPids = {
      for (final session in _registry.listAll())
        if (session.pid != null) session.pid!: session.name,
    };
    final findings = <DoctorFinding>[];
    for (final line in processStdout(ps).split('\n')) {
      final match = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$').firstMatch(line);
      if (match == null) continue;
      final command = match.group(3)!;
      final String server;
      if (command.contains('am instrument') &&
          command.contains('uiautomator2')) {
        server = 'UIAutomator2';
      } else if (command.contains('xcodebuild') &&
          command.contains('WebDriverAgent')) {
        server = 'WebDriverAgent';
      } else {
        continue;
      }
      final pid = int.parse(match.group(1)!);
      final parent = int.parse(match.group(2)!);
      if (sessionPids[pid] case final session?) {
        findings.add((
          status: DoctorStatus.ok,
          message: '$server (pid $pid) of native session "$session"',
          fix: null,
        ));
      } else if (parent == 1) {
        findings.add((
          status: DoctorStatus.problem,
          message: 'Orphaned $server (pid $pid): no native session or '
              'process owns it; it can block the port of a new session.',
          fix: 'kill $pid',
        ));
      } else {
        findings.add((
          status: DoctorStatus.ok,
          message: '$server (pid $pid) held by process $parent (e.g. an '
              'MCP server)',
          fix: null,
        ));
      }
    }
    return findings;
  }

  Future<List<DoctorFinding>> _checkSessions() async {
    return [
      for (final session in _registry.listAll())
        await _isServerRunning(session.baseUrl)
            ? (
                status: DoctorStatus.ok,
                message: 'Native session "${session.name}" '
                    '(${session.platform}, ${session.device}) is running',
                fix: null,
              )
            : (
                status: DoctorStatus.problem,
                message: 'Native session "${session.name}" '
                    '(${session.platform}, ${session.device}): its server '
                    'is not running.',
                fix: 'marionette --native-session ${session.name} '
                    'native-connect --platform ${session.platform}, or '
                    'native-disconnect to forget it.',
              ),
    ];
  }

  static Future<bool> _serverAnswers(String baseUrl) async {
    final client = WebDriverClient(baseUrl);
    try {
      return await client.status().timeout(const Duration(seconds: 3));
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
