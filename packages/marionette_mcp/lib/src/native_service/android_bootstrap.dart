import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_exceptions.dart';
import 'package:marionette_mcp/src/native_service/process.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';

export 'package:marionette_mcp/src/native_service/native_exceptions.dart'
    show AndroidBootstrapException, AndroidBootstrapFailure;
export 'package:marionette_mcp/src/native_service/process.dart'
    show ProcessRunner, ProcessStarter;

/// Signature for downloading a release asset, injectable for tests.
typedef ApkDownloader = Future<List<int>> Function(Uri url);

/// Returns whether a local TCP port is free to bind, injectable for tests.
typedef PortProbe = Future<bool> Function(int port);

/// Installs, starts, and exposes Appium's standalone UIAutomator2 server.
///
/// APKs are pinned to Appium UIAutomator2 server v10.3.2 and downloaded from:
/// https://github.com/appium/appium-uiautomator2-server/releases/tag/v10.3.2
/// Downloaded and cached APKs are verified against pinned SHA-256 checksums.
///
/// Set `MARIONETTE_UIA2_SERVER_APK` and `MARIONETTE_UIA2_TEST_APK` to use
/// local APKs instead (not checksum-verified). Downloads are cached under the
/// platform cache directory. An APK is only (re)installed when the copy on
/// the device differs from the local file.
///
/// The local port is chosen as described in
/// docs/native-lane-decisions.md#d10: `MARIONETTE_UIA2_PORT`, else the port
/// of an existing forward to this device, else the first free port from
/// [defaultLocalPort]. A healthy server behind an existing forward is reused
/// and left running on [dispose], because another Marionette process owns
/// it.
class AndroidBootstrap implements SharedServerBootstrap {
  AndroidBootstrap({
    this.serial,
    ProcessRunner? processRunner,
    ProcessStarter? processStarter,
    ApkDownloader? downloader,
    Directory? cacheDir,
    int? localPort,
    Map<String, String>? environment,
    PortProbe? isPortFree,
    Map<String, String>? apkSha256,
    this.detached = false,
    ProcessStarter? detachedProcessStarter,
  })  : _adb = AdbClient(serial: serial, processRunner: processRunner),
        _start =
            processStarter ?? (processRunner == null ? Process.start : null),
        _downloader = downloader ?? _download,
        _cacheDir = cacheDir ?? _defaultCacheDir(),
        _explicitLocalPort = localPort,
        _environment = environment ?? Platform.environment,
        _isPortFree = isPortFree ?? canBindLoopbackPort,
        _apkSha256 = apkSha256 ?? pinnedApkSha256,
        _startDetached = detachedProcessStarter ?? _startDetachedProcess;

  static const uia2Version = '10.3.2';
  static const _releaseBaseUrl =
      'https://github.com/appium/appium-uiautomator2-server/releases/download/'
      'v$uia2Version';
  static const _serverApkName = 'appium-uiautomator2-server-v$uia2Version.apk';
  static const _testApkName =
      'appium-uiautomator2-server-debug-androidTest.apk';
  static const _serverPackage = 'io.appium.uiautomator2.server';
  static const _testPackage = 'io.appium.uiautomator2.server.test';

  /// First local port tried when no port is configured or reused.
  static const defaultLocalPort = uia2DefaultLocalPort;

  /// UIAutomator2's port on the device.
  static const _devicePort = 6790;

  /// Environment variable that fixes the local port.
  static const portEnvironmentKey = uia2PortEnvironmentKey;

  /// SHA-256 of the v[uia2Version] release APKs, by file name.
  static const pinnedApkSha256 = {
    _serverApkName:
        '8463a42f7701bf29d07571089e189ff10178c5f6dab2b65ae8cce7018d44fbd8',
    _testApkName:
        '3eb8ed926f98a0b29248f0271c8d4df2fd34977298f79645e685338d971630cc',
  };

  final String? serial;

  /// Starts `adb shell am instrument -w` as a detached process that outlives
  /// this one — for the CLI, whose commands are separate processes
  /// (docs/native-lane-decisions.md#d4). Its pid is [detachedPid]. Without
  /// `-w` the server starts too, but cannot create sessions ("null
  /// UiAutomation"): the `am` process that provides UiAutomation is gone.
  /// Stop such a server with [stopServer].
  final bool detached;

  final ProcessStarter _startDetached;

  /// Pid of the detached `adb` process holding the instrumentation, if any.
  int? get detachedPid => _detachedPid;
  int? _detachedPid;

  static Future<Process> _startDetachedProcess(
    String executable,
    List<String> arguments,
  ) =>
      Process.start(executable, arguments, mode: ProcessStartMode.detached);

  final AdbClient _adb;
  final ProcessStarter? _start;
  final ApkDownloader _downloader;
  final Directory _cacheDir;
  final int? _explicitLocalPort;
  final Map<String, String> _environment;
  final PortProbe _isPortFree;
  final Map<String, String> _apkSha256;

  Process? _instrumentProcess;
  int? _instrumentExitCode;
  WebDriverClient? _healthClient;
  StreamSubscription<List<int>>? _instrumentStdout;
  StreamSubscription<List<int>>? _instrumentStderr;
  Uri? _readyUri;
  int? _localPort;

  /// Whether this instance started the server (and must stop it on
  /// [dispose]) rather than reusing one that was already running.
  bool _ownsServer = false;

  /// The `adb` client bound to [serial], shared with the connector.
  AdbClient get adb => _adb;

  /// Local port of the server, once [ensureServerReady] has chosen one.
  int? get localPort => _localPort;

  @override
  bool get startedServer => _ownsServer;

  /// Ensures UIAutomator2 is reachable and returns its local WebDriver URL.
  @override
  Future<Uri> ensureServerReady() async {
    final readyUri = _readyUri;
    final existingClient = _healthClient;
    if (readyUri != null &&
        existingClient != null &&
        await existingClient.status()) {
      return readyUri;
    }

    try {
      await _checkAdbAndDevice();

      final existingPort = await _existingForwardPort();
      if (existingPort != null && await _isHealthy(existingPort)) {
        // Another Marionette process (or an earlier session of this one that
        // was not torn down) owns this server; reuse it without taking over.
        _ownsServer = false;
        return _markReady(existingPort);
      }

      final port = existingPort ?? await _chooseLocalPort();
      _localPort = port;
      _ownsServer = true;

      final serverApk = await _resolveApk(
        environmentKey: 'MARIONETTE_UIA2_SERVER_APK',
        fileName: _serverApkName,
      );
      final testApk = await _resolveApk(
        environmentKey: 'MARIONETTE_UIA2_TEST_APK',
        fileName: _testApkName,
      );

      await _ensureInstalled(_serverPackage, serverApk);
      await _ensureInstalled(_testPackage, testApk);
      await _startInstrumentation();
      await _forwardPort(port);

      _healthClient = WebDriverClient('http://127.0.0.1:$port');
      await _waitUntilHealthy(_healthClient!, port);
      return _markReady(port);
    } on AndroidBootstrapException {
      await dispose();
      rethrow;
    } catch (error) {
      await dispose();
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.instrumentation,
        'Unexpected Android bootstrap failure: $error',
      );
    }
  }

  Uri _markReady(int port) {
    _localPort = port;
    _healthClient ??= WebDriverClient('http://127.0.0.1:$port');
    final uri = Uri.parse('http://127.0.0.1:$port');
    _readyUri = uri;
    return uri;
  }

  Future<void> _checkAdbAndDevice() async {
    ProcessResult version;
    try {
      version = await _adb.run(const ['version']);
    } on ProcessException catch (error) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.adbMissing,
        'adb was not found on PATH: ${error.message}',
      );
    }
    if (version.exitCode != 0) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.adbMissing,
        'adb is unavailable: ${processMessage(version)}',
      );
    }

    final state = await _adb.run(const ['get-state']);
    final deviceState = processStdout(state).trim();
    if (state.exitCode != 0 || deviceState != 'device') {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.deviceUnavailable,
        'Android device ${serial ?? '(default)'} is not online'
        '${deviceState.isEmpty ? '' : ' (state: $deviceState)'}: '
        '${processMessage(state)}',
      );
    }

    // UIAutomator2 cannot start before the first unlock after a restart
    // ("not encryption aware"); the health check would only time out.
    if (await _adb.isCurrentUserLocked()) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.deviceLocked,
        'Android device ${serial ?? '(default)'} is locked: after a restart '
        'its storage stays encrypted until the screen is unlocked, so '
        'UIAutomator2 cannot start.',
      );
    }
  }

  /// Port of an existing forward from this device to UIAutomator2. An
  /// explicit port (constructor or environment) disables reuse of other
  /// ports.
  Future<int?> _existingForwardPort() async {
    final deviceSerial = await _adb.resolveSerial();
    if (deviceSerial == null) return null;
    final forwarded = await _adb.forwardedLocalPort(deviceSerial, _devicePort);
    final fixed = _explicitLocalPort ?? _environmentPort();
    if (fixed != null && forwarded != fixed) return null;
    return forwarded;
  }

  int? _environmentPort() =>
      parseUia2PortEnvironment(_environment[portEnvironmentKey]);

  Future<int> _chooseLocalPort() => chooseUia2LocalPort(
        explicitPort: _explicitLocalPort,
        environmentValue: _environment[portEnvironmentKey],
        isPortFree: _isPortFree,
      );

  Future<File> _resolveApk({
    required String environmentKey,
    required String fileName,
  }) async {
    final overridePath = _environment[environmentKey];
    if (overridePath != null && overridePath.isNotEmpty) {
      final file = File(overridePath);
      if (!await file.exists()) {
        throw AndroidBootstrapException(
          AndroidBootstrapFailure.apkOverrideMissing,
          '$environmentKey points to a missing file: $overridePath',
        );
      }
      return file;
    }

    await _cacheDir.create(recursive: true);
    final cached = File('${_cacheDir.path}/$fileName');
    final expected = _apkSha256[fileName];
    if (await cached.exists() &&
        await cached.length() > 0 &&
        (expected == null || await _sha256Of(cached) == expected)) {
      return cached;
    }

    final url = Uri.parse('$_releaseBaseUrl/$fileName');
    final List<int> bytes;
    try {
      bytes = await _downloader(url);
      if (bytes.isEmpty) {
        throw const HttpException('Downloaded file was empty');
      }
    } catch (error) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.download,
        'Failed to download UIAutomator2 APK from $url: $error',
      );
    }

    final actual = sha256.convert(bytes).toString();
    if (expected != null && actual != expected) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.download,
        'Checksum mismatch for $url: expected $expected, got $actual.',
      );
    }

    final temporary = File('${cached.path}.download');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await cached.exists()) await cached.delete();
    return temporary.rename(cached.path);
  }

  /// Installs [apk] unless the device already has an identical copy of
  /// [packageName].
  Future<void> _ensureInstalled(String packageName, File apk) async {
    final installed = await _adb.installedApkSha256(packageName);
    if (installed != null && installed == await _sha256Of(apk)) return;
    await _install(apk);
  }

  Future<void> _install(File apk) async {
    final result = await _adb.run(['install', '-r', '-t', apk.path]);
    final message = processMessage(result);
    final alreadyInstalled =
        message.toLowerCase().contains('already installed');
    if (result.exitCode != 0 && !alreadyInstalled) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.install,
        'Failed to install ${apk.path}: $message',
      );
    }
  }

  Future<void> _startInstrumentation() async {
    final command = [
      'shell',
      'am',
      'instrument',
      '-e',
      'disableAnalytics',
      'true',
      '$_testPackage/androidx.test.runner.AndroidJUnitRunner',
    ];

    try {
      final heldCommand = [...command.take(3), '-w', ...command.skip(3)];
      if (detached) {
        // A detached process has no stdio and no exit code to watch.
        _detachedPid =
            (await _startDetached('adb', _adb.argumentsFor(heldCommand))).pid;
        return;
      }
      final starter = _start;
      if (starter == null) {
        // A supplied ProcessRunner must see every ADB call in unit tests.
        // Without `-w`, `am instrument` returns after launching the runner.
        final result = await _adb.run(command);
        if (result.exitCode != 0) {
          throw AndroidBootstrapException(
            AndroidBootstrapFailure.instrumentation,
            'Failed to start UIAutomator2 instrumentation: '
            '${processMessage(result)}',
          );
        }
        return;
      }

      final process = await starter('adb', _adb.argumentsFor(heldCommand));
      _instrumentProcess = process;
      _instrumentExitCode = null;
      _instrumentStdout = process.stdout.listen((_) {});
      _instrumentStderr = process.stderr.listen((_) {});
      unawaited(process.exitCode.then((code) => _instrumentExitCode = code));
    } on ProcessException catch (error) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.instrumentation,
        'Failed to start UIAutomator2 instrumentation: ${error.message}',
      );
    }
  }

  Future<void> _forwardPort(int port) async {
    final result = await _adb.run([
      'forward',
      'tcp:$port',
      'tcp:$_devicePort',
    ]);
    if (result.exitCode != 0) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.portForward,
        'Failed to forward local port $port to UIAutomator2: '
        '${processMessage(result)}',
      );
    }
  }

  Future<bool> _isHealthy(int port) async {
    final client = WebDriverClient('http://127.0.0.1:$port');
    try {
      return await client.status();
    } finally {
      client.close();
    }
  }

  Future<void> _waitUntilHealthy(WebDriverClient client, int port) async {
    const timeout = Duration(seconds: 30);
    const retryDelay = Duration(milliseconds: 500);
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      if (await client.status()) return;
      if (_instrumentExitCode case final exitCode?) {
        throw AndroidBootstrapException(
          AndroidBootstrapFailure.instrumentation,
          'UIAutomator2 instrumentation exited early with code $exitCode',
        );
      }
      await Future<void>.delayed(retryDelay);
    }

    throw AndroidBootstrapException(
      AndroidBootstrapFailure.healthCheck,
      'UIAutomator2 did not become healthy at '
      'http://127.0.0.1:$port within ${timeout.inSeconds} seconds',
    );
  }

  /// Stops instrumentation and removes the ADB forward, best-effort. A
  /// reused server (see the class docs) is left running.
  @override
  Future<void> dispose() async {
    _healthClient?.close();
    _healthClient = null;
    _readyUri = null;

    _instrumentProcess?.kill();
    _instrumentProcess = null;
    if (_detachedPid case final pid?) {
      Process.killPid(pid);
      _detachedPid = null;
    }
    await _instrumentStdout?.cancel();
    await _instrumentStderr?.cancel();
    _instrumentStdout = null;
    _instrumentStderr = null;

    final port = _localPort;
    final ownsServer = _ownsServer;
    _ownsServer = false;
    if (!ownsServer) return;

    try {
      await _adb.shell(['am', 'force-stop', _testPackage]);
    } catch (_) {
      // The host process above is the primary teardown path.
    }

    if (port != null) {
      try {
        await _adb.run(['forward', '--remove', 'tcp:$port']);
      } catch (_) {
        // Teardown is best-effort, including when adb has disappeared.
      }
    }
  }

  /// Stops a UIAutomator2 server started on the device behind [adb] (e.g.
  /// with [detached]) and removes the forward of local [port]. Best-effort.
  static Future<void> stopServer(AdbClient adb, {int? port}) async {
    for (final package in const [_testPackage, _serverPackage]) {
      try {
        await adb.shell(['am', 'force-stop', package]);
      } catch (_) {
        // The device may be gone; continue with the forward.
      }
    }
    if (port == null) return;
    try {
      await adb.run(['forward', '--remove', 'tcp:$port']);
    } catch (_) {
      // Already removed, or adb is gone.
    }
  }

  static Future<String> _sha256Of(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  /// Directory the UIAutomator2 APKs are downloaded to when no cache
  /// directory is given.
  static Directory get defaultCacheDir => _defaultCacheDir();

  /// File names of the pinned UIAutomator2 APKs in the cache directory.
  static const apkFileNames = [_serverApkName, _testApkName];

  /// Whether the cached APK [fileName] in [cacheDir] matches its pinned
  /// checksum; null when it is not cached. A mismatching copy is downloaded
  /// again by [ensureServerReady].
  static Future<bool?> cachedApkValid(
      Directory cacheDir, String fileName) async {
    final file = File('${cacheDir.path}/$fileName');
    if (!await file.exists()) return null;
    return await _sha256Of(file) == pinnedApkSha256[fileName];
  }

  static Directory _defaultCacheDir() {
    final environment = Platform.environment;
    final xdgCache = environment['XDG_CACHE_HOME'];
    if (xdgCache != null && xdgCache.isNotEmpty) {
      return Directory('$xdgCache/marionette_mcp/uia2');
    }
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home/.cache/marionette_mcp/uia2');
    }
    return Directory(
      '${Directory.systemTemp.path}/marionette_mcp/uia2',
    );
  }

  static Future<List<int>> _download(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode} ${response.reasonPhrase}',
          uri: url,
        );
      }
      // Must be awaited inside the try: a bare `return` would run the finally
      // (and force-close the client) while the body is still streaming,
      // aborting the transfer.
      return await response.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// First local port tried for the UIAutomator2 forward.
const uia2DefaultLocalPort = 8200;

/// How many ports from [uia2DefaultLocalPort] are tried before giving up.
const uia2PortSearchRange = 100;

/// Environment variable that fixes the UIAutomator2 local port.
const uia2PortEnvironmentKey = 'MARIONETTE_UIA2_PORT';

/// Parses the [uia2PortEnvironmentKey] value; null when unset or blank.
///
/// Throws [AndroidBootstrapException] for anything that is not a port.
int? parseUia2PortEnvironment(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final port = int.tryParse(raw.trim());
  if (port == null || port <= 0 || port > 65535) {
    throw AndroidBootstrapException(
      AndroidBootstrapFailure.portForward,
      '$uia2PortEnvironmentKey must be a port number, got "$raw".',
      hint: 'Set $uia2PortEnvironmentKey to a free TCP port (1-65535) or '
          'unset it to pick one automatically.',
    );
  }
  return port;
}

/// Chooses the local port for a new UIAutomator2 forward.
///
/// [explicitPort] (constructor argument, trusted as-is) wins; then the
/// [uia2PortEnvironmentKey] value, which must be free; otherwise the first
/// free port from [uia2DefaultLocalPort]. See
/// docs/native-lane-decisions.md#d10.
Future<int> chooseUia2LocalPort({
  required int? explicitPort,
  required String? environmentValue,
  required PortProbe isPortFree,
}) async {
  if (explicitPort != null) return explicitPort;

  final fromEnvironment = parseUia2PortEnvironment(environmentValue);
  if (fromEnvironment != null) {
    if (!await isPortFree(fromEnvironment)) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.portForward,
        'Port $fromEnvironment from $uia2PortEnvironmentKey is already in '
        'use.',
        hint: 'Free the port or point $uia2PortEnvironmentKey at another one; '
            'unset it to pick a free port automatically.',
      );
    }
    return fromEnvironment;
  }

  for (var port = uia2DefaultLocalPort;
      port < uia2DefaultLocalPort + uia2PortSearchRange;
      port++) {
    if (await isPortFree(port)) return port;
  }
  throw AndroidBootstrapException(
    AndroidBootstrapFailure.portForward,
    'No free local port in $uia2DefaultLocalPort-'
    '${uia2DefaultLocalPort + uia2PortSearchRange - 1}.',
    hint: 'Set $uia2PortEnvironmentKey to a free TCP port.',
  );
}
