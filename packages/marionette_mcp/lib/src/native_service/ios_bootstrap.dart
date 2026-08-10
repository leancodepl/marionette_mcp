import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

/// Signature for running a short-lived process — injectable for testing.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Signature for starting a long-running process — injectable for testing.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// Default cache directory for a previously-built WebDriverAgent runner.
Directory get defaultWdaCacheDir => Directory(
      '${Platform.environment['HOME'] ?? ''}/.cache/marionette_mcp/wda',
    );

/// Bootstraps WebDriverAgent (WDA) on an **iOS Simulator** and returns the
/// local HTTP base URL once `/status` is healthy.
///
/// ## Simulator-first (v1)
///
/// Real-device support needs codesigning, a development team, and usually
/// `iproxy` for port forwarding. This class intentionally targets the
/// simulator only: WDA binds to `localhost` on the Mac, so no `iproxy` is
/// required.
///
/// ## One-time WDA build (required)
///
/// Marionette does **not** clone or compile WebDriverAgent on first use —
/// that is too heavy for v1. Build WDA once yourself, then point Marionette
/// at the result via an environment variable.
///
/// Example (replace `UDID` with a simulator id from `xcrun simctl list`):
///
/// ```sh
/// git clone https://github.com/appium/WebDriverAgent.git
/// cd WebDriverAgent
/// xcodebuild build-for-testing \
///   -project WebDriverAgent.xcodeproj \
///   -scheme WebDriverAgentRunner \
///   -destination 'platform=iOS Simulator,id=UDID'
/// ```
///
/// Then either:
/// - set `MARIONETTE_WDA_XCTESTRUN` to the generated `.xctestrun` file under
///   DerivedData / Build/Products (preferred — runs WDA as an XCUITest), or
/// - set `MARIONETTE_WDA_BUNDLE` / `MARIONETTE_WDA_PATH` to the
///   `WebDriverAgentRunner-Runner.app` bundle (or copy it into
///   `~/.cache/marionette_mcp/wda/`).
///
/// ## Launch strategy
///
/// 1. Prefer `MARIONETTE_WDA_XCTESTRUN` → spawn
///    `xcodebuild test-without-building -xctestrun …` as a background process
///    (this is the standard Appium-style approach).
/// 2. Else use a runner `.app` from env / cache → `simctl install` +
///    `simctl launch`. **Limitation:** WDA is designed to run as an XCUITest;
///    a plain `simctl launch` often does **not** start the HTTP server.
///    Prefer the xctestrun path when possible.
/// 3. Else throw with the build instructions above.
class IosBootstrap {
  /// Creates a bootstrapper for the simulator identified by [udid].
  ///
  /// When [udid] is null, [ensureServerReady] picks the first booted
  /// simulator. [wdaLocalPort] defaults to WDA's usual `8100`.
  ///
  /// [wdaPath] overrides `MARIONETTE_WDA_PATH` / `MARIONETTE_WDA_BUNDLE` for
  /// the runner `.app` or a Products/DerivedData directory that contains one
  /// (or an `.xctestrun`).
  IosBootstrap({
    String? udid,
    ProcessRunner? processRunner,
    ProcessStarter? processStarter,
    int wdaLocalPort = 8100,
    String? wdaPath,
    Directory? cacheDir,
    Duration readyTimeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(milliseconds: 500),
    logging.Logger? logger,
  })  : _udid = udid,
        _run = processRunner ?? Process.run,
        _start = processStarter ?? Process.start,
        _wdaLocalPort = wdaLocalPort,
        _wdaPathOverride = wdaPath,
        _cacheDir = cacheDir ?? defaultWdaCacheDir,
        _readyTimeout = readyTimeout,
        _pollInterval = pollInterval,
        _logger = logger ?? logging.Logger('IosBootstrap');

  final String? _udid;
  final ProcessRunner _run;
  final ProcessStarter _start;
  final int _wdaLocalPort;
  final String? _wdaPathOverride;
  final Directory _cacheDir;
  final Duration _readyTimeout;
  final Duration _pollInterval;
  final logging.Logger _logger;

  String? _resolvedUdid;
  Process? _wdaProcess;
  int? _wdaExitCode;
  String? _simctlLaunchedUdid;
  String? _simctlLaunchedBundleId;

  /// Default WDA runner bundle id used by facebook/appium WebDriverAgent.
  static const wdaRunnerBundleId =
      'com.facebook.WebDriverAgentRunner.xctrunner';

  /// Local port WDA is expected to listen on.
  int get wdaLocalPort => _wdaLocalPort;

  /// Simulator UDID resolved during [ensureServerReady], if any.
  String? get resolvedUdid => _resolvedUdid;

  /// Ensures WDA is running and healthy, returning `http://127.0.0.1:$port`.
  ///
  /// Idempotent when the server is already responding on [wdaLocalPort].
  Future<Uri> ensureServerReady() async {
    _requireMacOS();

    final baseUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _wdaLocalPort,
    );

    _resolvedUdid = await _resolveSimulatorUdid();

    // Fast path: WDA is already healthy on the port for this simulator.
    if (await _isHealthy(baseUri)) {
      if (await _wdaServesSimulator(baseUri, _resolvedUdid!)) {
        return baseUri;
      }
      throw StateError(
        'Port $_wdaLocalPort is already in use by WebDriverAgent attached to '
        'a different simulator than $_resolvedUdid. Stop the other WDA '
        'instance or choose another wdaLocalPort.',
      );
    }
    final artifacts = _resolveWdaArtifacts();
    await _launchWda(artifacts, _resolvedUdid!);
    await _waitUntilHealthy(baseUri);
    return baseUri;
  }

  /// Kills any xcodebuild/WDA process started by this instance. Best-effort.
  Future<void> dispose() async {
    await _terminateSimctlLaunch();

    final process = _wdaProcess;
    _wdaProcess = null;
    if (process == null) return;
    try {
      process.kill(ProcessSignal.sigterm);
    } catch (_) {
      // Already exited or not killable.
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  void _requireMacOS() {
    if (!Platform.isMacOS) {
      throw StateError(
        'IosBootstrap requires macOS (WebDriverAgent / xcrun simctl). '
        'Current platform: ${Platform.operatingSystem}.',
      );
    }
  }

  Future<String> _resolveSimulatorUdid() async {
    final explicitUdid = _udid;
    if (explicitUdid != null && explicitUdid.isNotEmpty) return explicitUdid;

    final result =
        await _run('xcrun', ['simctl', 'list', 'devices', 'booted', '-j']);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to list booted simulators (exit ${result.exitCode}): '
        '${(result.stderr as String).trim()}',
      );
    }

    final decoded = jsonDecode(result.stdout as String);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected simctl JSON: expected an object');
    }

    final devices = decoded['devices'];
    if (devices is! Map<String, dynamic>) {
      throw StateError('Unexpected simctl JSON: missing devices map');
    }

    final booted = <String>[];
    for (final entry in devices.values) {
      if (entry is! List) continue;
      for (final device in entry) {
        if (device is! Map<String, dynamic>) continue;
        final state = device['state'] as String?;
        final udid = device['udid'] as String?;
        if (state == 'Booted' && udid != null && udid.isNotEmpty) {
          booted.add(udid);
        }
      }
    }

    if (booted.isEmpty) {
      throw StateError(
        'No booted iOS Simulator found. Boot one first, e.g.:\n'
        '  open -a Simulator\n'
        '  xcrun simctl boot "iPhone 16"\n'
        'Or pass an explicit udid to IosBootstrap.',
      );
    }

    final selected = booted.first;
    if (booted.length > 1) {
      _logger.info(
        'Multiple booted iOS Simulators (${booted.length}); '
        'using first: $selected. Pass an explicit udid to choose another.',
      );
    }
    return selected;
  }

  _WdaArtifacts _resolveWdaArtifacts() {
    final xctestrunEnv = Platform.environment['MARIONETTE_WDA_XCTESTRUN'];
    if (xctestrunEnv != null && xctestrunEnv.isNotEmpty) {
      final file = File(xctestrunEnv);
      if (file.existsSync()) {
        return _WdaArtifacts(xctestrunPath: file.path);
      }
      throw StateError(
        'MARIONETTE_WDA_XCTESTRUN is set but file not found: $xctestrunEnv',
      );
    }

    final pathOverride = _wdaPathOverride;
    final candidates = <String>[
      if (pathOverride != null && pathOverride.isNotEmpty) pathOverride,
      if (Platform.environment['MARIONETTE_WDA_BUNDLE'] case final String b
          when b.isNotEmpty)
        b,
      if (Platform.environment['MARIONETTE_WDA_PATH'] case final String p
          when p.isNotEmpty)
        p,
    ];

    for (final path in candidates) {
      final resolved = _artifactsFromPath(path);
      if (resolved != null) return resolved;
    }

    if (_cacheDir.existsSync()) {
      final fromCache = _findArtifactsUnder(_cacheDir);
      if (fromCache != null) return fromCache;
    }

    throw StateError(_missingWdaMessage());
  }

  _WdaArtifacts? _artifactsFromPath(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: true);
    if (type == FileSystemEntityType.notFound) return null;

    if (type == FileSystemEntityType.file) {
      if (path.endsWith('.xctestrun')) {
        return _WdaArtifacts(xctestrunPath: path);
      }
      return null;
    }

    // Directory: .app bundle, Products folder, or DerivedData tree.
    if (path.endsWith('.app')) {
      return _WdaArtifacts(bundlePath: path);
    }

    return _findArtifactsUnder(Directory(path));
  }

  _WdaArtifacts? _findArtifactsUnder(Directory dir) {
    if (!dir.existsSync()) return null;

    // Prefer xctestrun (proper XCUITest launch).
    try {
      final xctestrun = dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.xctestrun'))
          .toList();
      if (xctestrun.isNotEmpty) {
        return _WdaArtifacts(xctestrunPath: xctestrun.first.path);
      }
    } on FileSystemException {
      // Unreadable tree — fall through to .app search.
    }

    try {
      final apps = dir
          .listSync(recursive: true, followLinks: false)
          .whereType<Directory>()
          .where((d) => d.path.endsWith('WebDriverAgentRunner-Runner.app'))
          .toList();
      if (apps.isNotEmpty) {
        return _WdaArtifacts(bundlePath: apps.first.path);
      }
    } on FileSystemException {
      return null;
    }

    return null;
  }

  Future<void> _launchWda(_WdaArtifacts artifacts, String udid) async {
    if (artifacts.xctestrunPath != null) {
      await _launchViaXcodebuild(artifacts.xctestrunPath!, udid);
      return;
    }
    if (artifacts.bundlePath != null) {
      await _launchViaSimctl(artifacts.bundlePath!, udid);
      return;
    }
    throw StateError(_missingWdaMessage());
  }

  Future<void> _launchViaXcodebuild(String xctestrunPath, String udid) async {
    // Standard Appium approach: run the already-built test without rebuilding.
    // WDA binds to localhost:8100 on the Mac when targeting a simulator.
    final process = await _start('xcodebuild', [
      'test-without-building',
      '-xctestrun',
      xctestrunPath,
      '-destination',
      'platform=iOS Simulator,id=$udid',
    ]);
    _attachProcess(process);
  }

  Future<void> _launchViaSimctl(String bundlePath, String udid) async {
    // Best-effort fallback. WDA normally must run as an XCUITest host; a
    // plain simctl launch frequently never opens the HTTP server. Prefer
    // MARIONETTE_WDA_XCTESTRUN when available.
    final install =
        await _run('xcrun', ['simctl', 'install', udid, bundlePath]);
    if (install.exitCode != 0) {
      throw StateError(
        'simctl install failed (exit ${install.exitCode}): '
        '${(install.stderr as String).trim()}',
      );
    }

    const bundleId = wdaRunnerBundleId;
    final launch = await _run('xcrun', [
      'simctl',
      'launch',
      udid,
      bundleId,
    ]);
    if (launch.exitCode != 0) {
      throw StateError(
        'simctl launch of $bundleId failed (exit ${launch.exitCode}): '
        '${(launch.stderr as String).trim()}\n'
        'Note: WDA typically needs to run as an XCUITest. Prefer setting '
        'MARIONETTE_WDA_XCTESTRUN and using xcodebuild test-without-building.',
      );
    }

    _simctlLaunchedUdid = udid;
    _simctlLaunchedBundleId = bundleId;
  }

  Future<void> _terminateSimctlLaunch() async {
    final udid = _simctlLaunchedUdid;
    final bundleId = _simctlLaunchedBundleId;
    _simctlLaunchedUdid = null;
    _simctlLaunchedBundleId = null;
    if (udid == null || bundleId == null) return;

    try {
      await _run('xcrun', ['simctl', 'terminate', udid, bundleId]);
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  Future<bool> _wdaServesSimulator(Uri baseUri, String expectedUdid) async {
    final client = WebDriverClient(baseUri.toString());
    try {
      final info = await client.wdaDeviceInfo();
      final udid = info['udid'];
      return udid is String && udid == expectedUdid;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  void _attachProcess(Process process) {
    _wdaProcess = process;
    _wdaExitCode = null;
    // Drain pipes so a chatty xcodebuild cannot fill OS buffers and stall.
    process.stdout.listen((_) {});
    process.stderr.listen((_) {});
    process.exitCode.then((code) {
      _wdaExitCode = code;
      if (identical(_wdaProcess, process)) {
        _wdaProcess = null;
      }
    });
  }

  Future<bool> _isHealthy(Uri baseUri) async {
    final client = WebDriverClient(baseUri.toString());
    try {
      return await client.status();
    } finally {
      client.close();
    }
  }

  Future<void> _waitUntilHealthy(Uri baseUri) async {
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy(baseUri)) return;

      final exitCode = _wdaExitCode;
      if (exitCode != null) {
        throw StateError(
          'WebDriverAgent process exited with code $exitCode before becoming '
          'ready on $baseUri. Check xcodebuild output and that the '
          'xctestrun matches this simulator runtime.',
        );
      }

      await Future<void>.delayed(_pollInterval);
    }

    throw StateError(
      'WebDriverAgent did not become ready at $baseUri within '
      '${_readyTimeout.inSeconds}s. WDA is often slow to start; verify the '
      'runner was built for this simulator and that port $_wdaLocalPort is '
      'free.',
    );
  }

  String _missingWdaMessage() => '''
No prebuilt WebDriverAgent found.

Marionette does not clone/build WDA automatically (simulator-first v1).
Build it once, then set an environment variable:

  git clone https://github.com/appium/WebDriverAgent.git
  cd WebDriverAgent
  xcodebuild build-for-testing \\
    -project WebDriverAgent.xcodeproj \\
    -scheme WebDriverAgentRunner \\
    -destination 'platform=iOS Simulator,id=<UDID>'

Then set one of:
  MARIONETTE_WDA_XCTESTRUN=/path/to/*.xctestrun   # preferred
  MARIONETTE_WDA_BUNDLE=/path/to/WebDriverAgentRunner-Runner.app
  MARIONETTE_WDA_PATH=/path/to/app/or/DerivedData/Products

Or copy the runner into ${_cacheDir.path}/
''';
}

class _WdaArtifacts {
  const _WdaArtifacts({this.xctestrunPath, this.bundlePath});

  final String? xctestrunPath;
  final String? bundlePath;
}
