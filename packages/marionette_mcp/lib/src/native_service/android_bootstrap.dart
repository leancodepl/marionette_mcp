import 'dart:async';
import 'dart:io';

import 'webdriver_client.dart';

/// Signature for running an ADB command, injectable for tests.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Signature for starting the long-running instrumentation process.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// Signature for downloading a release asset, injectable for tests.
typedef ApkDownloader = Future<List<int>> Function(Uri url);

/// The stage at which Android native automation bootstrap failed.
enum AndroidBootstrapFailure {
  adbMissing,
  deviceUnavailable,
  download,
  install,
  instrumentation,
  portForward,
  healthCheck,
}

/// A failure while preparing the on-device UIAutomator2 server.
class AndroidBootstrapException implements Exception {
  const AndroidBootstrapException(this.failure, this.message);

  final AndroidBootstrapFailure failure;
  final String message;

  @override
  String toString() => 'AndroidBootstrapException($failure): $message';
}

/// Installs, starts, and exposes Appium's standalone UIAutomator2 server.
///
/// APKs are pinned to Appium UIAutomator2 server v10.3.2 and downloaded from:
/// https://github.com/appium/appium-uiautomator2-server/releases/tag/v10.3.2
///
/// Set `MARIONETTE_UIA2_SERVER_APK` and `MARIONETTE_UIA2_TEST_APK` to use
/// local APKs instead. Downloads are cached under the platform cache directory.
class AndroidBootstrap {
  AndroidBootstrap({
    this.serial,
    ProcessRunner? processRunner,
    ProcessStarter? processStarter,
    ApkDownloader? downloader,
    Directory? cacheDir,
    this.localPort = 8200,
  })  : _run = processRunner ?? Process.run,
        _start =
            processStarter ?? (processRunner == null ? Process.start : null),
        _downloader = downloader ?? _download,
        _cacheDir = cacheDir ?? _defaultCacheDir();

  static const uia2Version = '10.3.2';
  static const _releaseBaseUrl =
      'https://github.com/appium/appium-uiautomator2-server/releases/download/'
      'v$uia2Version';
  static const _serverApkName = 'appium-uiautomator2-server-v$uia2Version.apk';
  static const _testApkName =
      'appium-uiautomator2-server-debug-androidTest.apk';

  final String? serial;
  final int localPort;
  final ProcessRunner _run;
  final ProcessStarter? _start;
  final ApkDownloader _downloader;
  final Directory _cacheDir;

  Process? _instrumentProcess;
  int? _instrumentExitCode;
  WebDriverClient? _healthClient;
  StreamSubscription<List<int>>? _instrumentStdout;
  StreamSubscription<List<int>>? _instrumentStderr;
  Uri? _readyUri;

  /// Ensures UIAutomator2 is reachable and returns its local WebDriver URL.
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

      final serverApk = await _resolveApk(
        environmentKey: 'MARIONETTE_UIA2_SERVER_APK',
        fileName: _serverApkName,
      );
      final testApk = await _resolveApk(
        environmentKey: 'MARIONETTE_UIA2_TEST_APK',
        fileName: _testApkName,
      );

      await _install(serverApk);
      await _install(testApk);
      await _startInstrumentation();
      await _forwardPort();

      final baseUri = Uri.parse('http://127.0.0.1:$localPort');
      _healthClient = WebDriverClient(baseUri.toString());
      await _waitUntilHealthy(_healthClient!);
      _readyUri = baseUri;
      return baseUri;
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

  Future<void> _checkAdbAndDevice() async {
    ProcessResult version;
    try {
      version = await _adb(const ['version']);
    } on ProcessException catch (error) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.adbMissing,
        'adb was not found on PATH: ${error.message}',
      );
    }
    if (version.exitCode != 0) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.adbMissing,
        'adb is unavailable: ${_processMessage(version)}',
      );
    }

    final state = await _adb(const ['get-state']);
    final deviceState = _stdout(state).trim();
    if (state.exitCode != 0 || deviceState != 'device') {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.deviceUnavailable,
        'Android device ${serial ?? '(default)'} is not online'
        '${deviceState.isEmpty ? '' : ' (state: $deviceState)'}: '
        '${_processMessage(state)}',
      );
    }
  }

  Future<File> _resolveApk({
    required String environmentKey,
    required String fileName,
  }) async {
    final overridePath = Platform.environment[environmentKey];
    if (overridePath != null && overridePath.isNotEmpty) {
      final file = File(overridePath);
      if (!await file.exists()) {
        throw AndroidBootstrapException(
          AndroidBootstrapFailure.download,
          '$environmentKey points to a missing file: $overridePath',
        );
      }
      return file;
    }

    await _cacheDir.create(recursive: true);
    final cached = File('${_cacheDir.path}/$fileName');
    if (await cached.exists() && await cached.length() > 0) return cached;

    final url = Uri.parse('$_releaseBaseUrl/$fileName');
    try {
      final bytes = await _downloader(url);
      if (bytes.isEmpty) {
        throw const HttpException('Downloaded file was empty');
      }
      final temporary = File('${cached.path}.download');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await cached.exists()) await cached.delete();
      return temporary.rename(cached.path);
    } catch (error) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.download,
        'Failed to download UIAutomator2 APK from $url: $error',
      );
    }
  }

  Future<void> _install(File apk) async {
    final result = await _adb(['install', '-r', '-t', apk.path]);
    final message = _processMessage(result);
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
      'io.appium.uiautomator2.server.test/'
          'androidx.test.runner.AndroidJUnitRunner',
    ];

    try {
      final starter = _start;
      if (starter == null) {
        // A supplied ProcessRunner must see every ADB call in unit tests.
        // Without `-w`, `am instrument` returns after launching the runner.
        final result = await _adb(command);
        if (result.exitCode != 0) {
          throw AndroidBootstrapException(
            AndroidBootstrapFailure.instrumentation,
            'Failed to start UIAutomator2 instrumentation: '
            '${_processMessage(result)}',
          );
        }
        return;
      }

      final process = await starter(
        'adb',
        _adbArguments([...command.take(3), '-w', ...command.skip(3)]),
      );
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

  Future<void> _forwardPort() async {
    final result = await _adb([
      'forward',
      'tcp:$localPort',
      'tcp:6790',
    ]);
    if (result.exitCode != 0) {
      throw AndroidBootstrapException(
        AndroidBootstrapFailure.portForward,
        'Failed to forward local port $localPort to UIAutomator2: '
        '${_processMessage(result)}',
      );
    }
  }

  Future<void> _waitUntilHealthy(WebDriverClient client) async {
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
      'http://127.0.0.1:$localPort within ${timeout.inSeconds} seconds',
    );
  }

  Future<ProcessResult> _adb(List<String> arguments) =>
      _run('adb', _adbArguments(arguments));

  List<String> _adbArguments(List<String> arguments) => [
        if (serial != null) ...['-s', serial!],
        ...arguments,
      ];

  /// Stops instrumentation and removes the ADB forward, best-effort.
  Future<void> dispose() async {
    _healthClient?.close();
    _healthClient = null;
    _readyUri = null;

    _instrumentProcess?.kill();
    _instrumentProcess = null;
    await _instrumentStdout?.cancel();
    await _instrumentStderr?.cancel();
    _instrumentStdout = null;
    _instrumentStderr = null;

    try {
      await _adb([
        'shell',
        'am',
        'force-stop',
        'io.appium.uiautomator2.server.test',
      ]);
    } catch (_) {
      // The host process above is the primary teardown path.
    }

    try {
      await _adb(['forward', '--remove', 'tcp:$localPort']);
    } catch (_) {
      // Teardown is best-effort, including when adb has disappeared.
    }
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

  static String _stdout(ProcessResult result) =>
      result.stdout is String ? result.stdout as String : '${result.stdout}';

  static String _processMessage(ProcessResult result) {
    final stderr =
        result.stderr is String ? (result.stderr as String).trim() : '';
    final stdout = _stdout(result).trim();
    if (stderr.isNotEmpty) return stderr;
    if (stdout.isNotEmpty) return stdout;
    return 'process exited with code ${result.exitCode}';
  }
}
