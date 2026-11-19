import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/native_service/bootstrap_helpers.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/process.dart';
import 'package:marionette_mcp/src/native_service/simctl_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

export 'package:marionette_mcp/src/native_service/native_exceptions.dart'
    show IosBootstrapException, IosBootstrapFailure;
export 'package:marionette_mcp/src/native_service/process.dart'
    show ProcessRunner, ProcessStarter;

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
/// Then set `MARIONETTE_WDA_XCTESTRUN` to the generated `.xctestrun` file
/// under DerivedData / Build/Products, set `MARIONETTE_WDA_PATH` to a
/// directory that contains it, or copy the build products into the
/// `marionette_mcp/wda` cache directory.
///
/// ## Launch strategy
///
/// WDA runs as an XCUITest: `xcodebuild test-without-building -xctestrun …`
/// as a background process (the standard Appium approach). Without an
/// `.xctestrun`, [ensureServerReady] throws with the build instructions above.
///
/// Failures are reported as [IosBootstrapException] with the failing stage.
class IosBootstrap implements NativeServerBootstrap {
  /// Creates a bootstrapper for the simulator identified by [udid].
  ///
  /// When [udid] is null, [ensureServerReady] picks the first booted
  /// simulator. [wdaLocalPort] defaults to WDA's usual `8100`.
  ///
  /// [wdaPath], an `.xctestrun` file or a Products/DerivedData directory
  /// that contains one, is searched before `MARIONETTE_WDA_PATH` and the
  /// cache directory.
  ///
  /// [operatingSystem] is the host OS in [Platform.operatingSystem] form; it
  /// defaults to the real host.
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
    this.detached = false,
    ProcessStarter? detachedProcessStarter,
    PortProbe? isPortFree,
    String? operatingSystem,
  })  : _udid = udid,
        _isPortFree = isPortFree ?? canBindLoopbackPort,
        _operatingSystem = operatingSystem ?? Platform.operatingSystem,
        _startDetached = detachedProcessStarter ?? startDetachedProcess,
        _simctl = SimctlClient(processRunner: processRunner),
        _start = processStarter ?? Process.start,
        _wdaLocalPort = wdaLocalPort,
        _wdaPathOverride = wdaPath,
        _cacheDir = cacheDir ?? nativeCacheDir('wda'),
        _readyTimeout = readyTimeout,
        _pollInterval = pollInterval,
        _logger = logger ?? logging.Logger('IosBootstrap');

  /// Default WDA runner bundle id used by facebook/appium WebDriverAgent.
  static const _wdaRunnerBundleId =
      'com.facebook.WebDriverAgentRunner.xctrunner';

  /// How long [dispose] waits for xcodebuild to exit after SIGTERM.
  static const _killTimeout = Duration(seconds: 2);

  /// Starts `xcodebuild` as a detached process that outlives this one — for
  /// the CLI, whose commands are separate processes.
  /// Its pid is [detachedPid]; [dispose]
  /// leaves it running.
  final bool detached;

  final ProcessStarter _startDetached;
  final PortProbe _isPortFree;
  final String _operatingSystem;
  final String? _udid;
  final SimctlClient _simctl;
  final ProcessStarter _start;
  final int _wdaLocalPort;
  final String? _wdaPathOverride;
  final Directory _cacheDir;
  final Duration _readyTimeout;
  final Duration _pollInterval;
  final logging.Logger _logger;

  String? _resolvedUdid;
  ServerProcess? _wdaProcess;
  int? _detachedPid;

  /// Pid of the `xcodebuild` started in [detached] mode, if any.
  int? get detachedPid => _detachedPid;

  /// Local port WDA is expected to listen on.
  int get wdaLocalPort => _wdaLocalPort;

  /// Simulator UDID resolved during [ensureServerReady], if any.
  String? get resolvedUdid => _resolvedUdid;

  /// Ensures WDA is running and healthy, returning `http://127.0.0.1:$port`.
  ///
  /// Idempotent when the server is already responding on [wdaLocalPort].
  @override
  Future<Uri> ensureServerReady() async {
    _requireMacOS();

    final baseUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _wdaLocalPort,
    );

    _resolvedUdid = await _resolveSimulatorUdid();

    // Fast path: WDA is already healthy on the port for this simulator.
    if (await isServerHealthy('$baseUri')) {
      if (await _wdaServesSimulator(_resolvedUdid!)) {
        return baseUri;
      }
      throw IosBootstrapException(
        IosBootstrapFailure.portConflict,
        'Port $_wdaLocalPort is already in use by WebDriverAgent attached to '
        'a different simulator than $_resolvedUdid. Marionette supports one '
        'iOS Simulator at a time.',
      );
    }
    // Something else listening there would make WDA fail to bind and the
    // health wait run into its timeout.
    if (!await _isPortFree(_wdaLocalPort)) {
      throw IosBootstrapException(
        IosBootstrapFailure.portConflict,
        'Port $_wdaLocalPort, which WebDriverAgent needs, is used by another '
        'program.',
        hint: 'Find it with "lsof -nP -iTCP:$_wdaLocalPort -sTCP:LISTEN" and '
            'stop it, then retry.',
      );
    }
    final xctestrunPath = _resolveXctestrun();
    try {
      await _launchViaXcodebuild(xctestrunPath, _resolvedUdid!);
      await _waitUntilHealthy(baseUri);
    } catch (_) {
      // Do not leave a half-started xcodebuild/WDA behind.
      if (_detachedPid case final pid?) {
        Process.killPid(pid);
        _detachedPid = null;
      }
      await dispose();
      rethrow;
    }
    return baseUri;
  }

  /// Kills any xcodebuild/WDA process started by this instance: SIGTERM,
  /// then SIGKILL (logged) when it has not exited after [_killTimeout].
  @override
  Future<void> dispose() async {
    final process = _wdaProcess;
    _wdaProcess = null;
    if (process == null) return;
    await process.kill();
    try {
      await process.exited.timeout(_killTimeout);
    } on TimeoutException {
      _logger.warning(
        'xcodebuild did not exit within ${_killTimeout.inSeconds}s of '
        'SIGTERM; sending SIGKILL',
      );
      await process.kill(ProcessSignal.sigkill);
    }
  }

  void _requireMacOS() {
    if (_operatingSystem != 'macos') {
      throw IosBootstrapException(
        IosBootstrapFailure.notMacOS,
        'IosBootstrap requires macOS (WebDriverAgent / xcrun simctl). '
        'Current platform: $_operatingSystem.',
      );
    }
  }

  /// Returns [_udid] when that simulator is booted, else the first booted
  /// simulator. An explicit but shut-down simulator is an error: xcodebuild
  /// would otherwise boot it headless (slowly, without a window).
  Future<String> _resolveSimulatorUdid() async {
    final explicitUdid = _udid;
    final List<String> booted;
    try {
      booted = await _simctl.listBootedUdids();
    } on ProcessCommandException catch (error) {
      throw IosBootstrapException(
        IosBootstrapFailure.simctl,
        'Failed to list booted simulators: $error',
      );
    } on FormatException catch (error) {
      throw IosBootstrapException(
        IosBootstrapFailure.simctl,
        'Failed to parse simctl output: ${error.message}',
      );
    } on ProcessException catch (error) {
      throw _xcrunFailed(error);
    }

    if (explicitUdid != null && explicitUdid.isNotEmpty) {
      if (booted.contains(explicitUdid)) return explicitUdid;
      throw IosBootstrapException(
        IosBootstrapFailure.noBootedSimulator,
        'iOS Simulator $explicitUdid is not booted'
        '${booted.isEmpty ? '' : ' (booted: ${booted.join(', ')})'}.',
        hint: 'Boot it first (`xcrun simctl boot $explicitUdid` and '
            '`open -a Simulator`), or omit udid to use a booted one.',
      );
    }

    if (booted.isEmpty) {
      throw IosBootstrapException(
        IosBootstrapFailure.noBootedSimulator,
        'No booted iOS Simulator found.',
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

  /// The `.xctestrun` of the WDA build: `MARIONETTE_WDA_XCTESTRUN`, else the
  /// first one found under `wdaPath`, `MARIONETTE_WDA_PATH` or the cache
  /// directory.
  String _resolveXctestrun() {
    final xctestrunEnv = Platform.environment['MARIONETTE_WDA_XCTESTRUN'];
    if (xctestrunEnv != null && xctestrunEnv.isNotEmpty) {
      if (File(xctestrunEnv).existsSync()) return xctestrunEnv;
      throw IosBootstrapException(
        IosBootstrapFailure.wdaArtifactsMissing,
        'MARIONETTE_WDA_XCTESTRUN is set but file not found: $xctestrunEnv',
      );
    }

    final searchPaths = [
      if (_wdaPathOverride case final path? when path.isNotEmpty) path,
      if (Platform.environment['MARIONETTE_WDA_PATH'] case final path?
          when path.isNotEmpty)
        path,
      _cacheDir.path,
    ];
    for (final path in searchPaths) {
      if (_findXctestrun(path) case final xctestrun?) return xctestrun;
    }

    throw IosBootstrapException(
      IosBootstrapFailure.wdaArtifactsMissing,
      _missingWdaMessage(),
    );
  }

  /// [path] itself when it is an `.xctestrun` file, else the first
  /// `.xctestrun` in the directory tree at [path].
  String? _findXctestrun(String path) {
    switch (FileSystemEntity.typeSync(path)) {
      case FileSystemEntityType.file:
        return path.endsWith('.xctestrun') ? path : null;
      case FileSystemEntityType.directory:
        try {
          return Directory(path)
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .map((file) => file.path)
              .where((filePath) => filePath.endsWith('.xctestrun'))
              .firstOrNull;
        } on FileSystemException catch (error) {
          throw IosBootstrapException(
            IosBootstrapFailure.wdaArtifactsMissing,
            'Cannot search $path for an .xctestrun: ${error.message}',
            hint: 'Make ${error.path ?? path} readable, or point '
                'MARIONETTE_WDA_XCTESTRUN at the .xctestrun file.',
          );
        }
      default:
        return null;
    }
  }

  Future<void> _launchViaXcodebuild(String xctestrunPath, String udid) async {
    // Standard Appium approach: run the already-built test without rebuilding.
    // WDA binds to localhost:8100 on the Mac when targeting a simulator.
    final arguments = [
      'test-without-building',
      '-xctestrun',
      xctestrunPath,
      '-destination',
      'platform=iOS Simulator,id=$udid',
    ];
    if (detached) {
      try {
        // A detached process has no stdio and no exit code to watch.
        _detachedPid = (await _startDetached('xcodebuild', arguments)).pid;
      } on ProcessException catch (error) {
        throw IosBootstrapException(
          IosBootstrapFailure.launch,
          'Failed to start xcodebuild: ${error.message}',
        );
      }
      return;
    }
    final Process process;
    try {
      process = await _start('xcodebuild', arguments);
    } on ProcessException catch (error) {
      throw IosBootstrapException(
        IosBootstrapFailure.launch,
        'Failed to start xcodebuild: ${error.message}',
      );
    }
    _wdaProcess = ServerProcess(process);
  }

  /// Whether the WDA answering on the port runs on [expectedUdid].
  ///
  /// WDA does not report the simulator UDID (`/wda/device/info` has a
  /// per-app `uuid` only), so the check looks for the runner app inside that
  /// simulator: simulators share the host network, so only one WDA can
  /// listen on the port.
  ///
  /// When `launchctl` fails it throws an [IosBootstrapFailure.simctl]
  /// failure: an unknown owner of the port is no proof of a port conflict.
  Future<bool> _wdaServesSimulator(String expectedUdid) async {
    try {
      return await _simctl.isAppRunning(expectedUdid, _wdaRunnerBundleId);
    } on ProcessCommandException catch (error) {
      throw IosBootstrapException(
        IosBootstrapFailure.simctl,
        'Failed to check whether the WebDriverAgent on port $_wdaLocalPort '
        'serves simulator $expectedUdid: $error',
      );
    } on ProcessException catch (error) {
      throw _xcrunFailed(error);
    }
  }

  IosBootstrapException _xcrunFailed(ProcessException error) =>
      IosBootstrapException(
        IosBootstrapFailure.simctl,
        'Failed to run xcrun: ${error.message}',
      );

  Future<void> _waitUntilHealthy(Uri baseUri) async {
    final client = WebDriverClient(baseUri.toString());
    try {
      await waitUntilHealthy(
        client,
        timeout: _readyTimeout,
        pollInterval: _pollInterval,
        exitCode: () => _wdaProcess?.exitCode,
        exited: (exitCode) => IosBootstrapException(
          IosBootstrapFailure.launch,
          'WebDriverAgent process exited with code $exitCode before becoming '
          'ready on $baseUri.',
        ),
        timedOut: () => IosBootstrapException(
          IosBootstrapFailure.healthCheck,
          'WebDriverAgent did not become ready at $baseUri within '
          '${_readyTimeout.inSeconds}s.',
        ),
      );
    } finally {
      client.close();
    }
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
  MARIONETTE_WDA_XCTESTRUN=/path/to/*.xctestrun
  MARIONETTE_WDA_PATH=/path/to/DerivedData/Build/Products

Or copy the build products (with the .xctestrun) into ${_cacheDir.path}/
''';
}
