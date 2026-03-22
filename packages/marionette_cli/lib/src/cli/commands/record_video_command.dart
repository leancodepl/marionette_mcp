import 'dart:async';
import 'dart:io';

import 'package:marionette_cli/src/cli/adb_helper.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/video/ffmpeg_process.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/tcp_frame_reader.dart';
import 'package:marionette_mcp/src/video/video_options.dart';
import 'package:marionette_mcp/src/video/video_recorder.dart';
import 'package:marionette_mcp/src/video/ws_frame_server.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

/// Signature for checking whether ffmpeg is available.
typedef FfmpegAvailabilityChecker = Future<bool> Function({String ffmpegPath});

/// Signature for creating a RecordingSession with its full pipeline.
typedef RecordingSessionFactory =
    Future<RecordingSession> Function({
      required int frameServerPort,
      required String outputFile,
      required int width,
      required int height,
      required String ffmpegPath,
    });

/// Signature for creating a RecordingSession using a WebSocket frame source.
typedef WsRecordingSessionFactory =
    Future<RecordingSession> Function({
      required FrameSource frameSource,
      required String outputFile,
      required int width,
      required int height,
      required String ffmpegPath,
    });

/// Signature for binding a [WebSocketFrameServer] on an OS-assigned port.
typedef WsFrameServerFactory = Future<WebSocketFrameServer> Function();

/// Signature for resolving the platform's file-open command.
typedef OpenCommandResolver = String? Function();

/// Signature for creating an [AdbHelper] instance.
typedef AdbHelperFactory = AdbHelper Function();

/// Records a video of a running Flutter app via the screencast pipeline.
class RecordVideoCommand extends InstanceCommand {
  RecordVideoCommand(
    this._registry, {
    FfmpegAvailabilityChecker? ffmpegChecker,
    RecordingSessionFactory? sessionFactory,
    WsRecordingSessionFactory? wsSessionFactory,
    WsFrameServerFactory? wsFrameServerFactory,
    OpenCommandResolver? openCommandResolver,
    AdbHelperFactory? adbHelperFactory,
  }) : _ffmpegChecker = ffmpegChecker ?? FfmpegProcess.isAvailable,
       _sessionFactory = sessionFactory ?? _defaultSessionFactory,
       _wsSessionFactory = wsSessionFactory ?? _defaultWsSessionFactory,
       _wsFrameServerFactory =
           wsFrameServerFactory ?? WebSocketFrameServer.bind,
       _openCommandResolver = openCommandResolver ?? _defaultOpenCommand,
       _adbHelperFactory = adbHelperFactory ?? AdbHelper.new {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path for the video. Must end with .webm.',
        mandatory: true,
      )
      ..addFlag(
        'open',
        help: 'Open the video after recording.',
        defaultsTo: false,
      )
      ..addOption(
        'duration',
        abbr: 'd',
        help: 'Recording duration in seconds. Records until Ctrl+C if not set.',
      )
      ..addOption(
        'width',
        help:
            'Video width in pixels. Must not exceed the viewport width.\n'
            'Default: native viewport (native) or 1280 (web).',
      )
      ..addOption(
        'height',
        help:
            'Video height in pixels. Must not exceed the viewport height.\n'
            'Default: native viewport (native) or 720 (web).',
      )
      ..addOption(
        'ffmpeg-path',
        help: 'Path to ffmpeg binary.',
        defaultsTo: 'ffmpeg',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Print diagnostic details (probe response, frame counts).',
        defaultsTo: false,
      )
      ..addOption(
        'transport',
        help:
            'Frame transport mode.\n'
            '  auto: try TCP, fall back to reverse-WS via adb (default)\n'
            '  tcp:  force TCP (fail if unreachable)\n'
            '  ws:   force reverse-WS (requires adb)',
        defaultsTo: 'auto',
        allowed: ['auto', 'tcp', 'ws'],
      )
      ..addOption(
        'frame-port',
        help:
            'Use a specific TCP port for frame streaming instead of\n'
            'auto-negotiation. Useful when adb reverse is unavailable.\n'
            'Example: adb forward tcp:9999 tcp:<flutter-port>',
      );
  }

  final InstanceRegistry _registry;
  final FfmpegAvailabilityChecker _ffmpegChecker;
  final RecordingSessionFactory _sessionFactory;
  final WsRecordingSessionFactory _wsSessionFactory;
  final WsFrameServerFactory _wsFrameServerFactory;
  final OpenCommandResolver _openCommandResolver;
  final AdbHelperFactory _adbHelperFactory;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'record-video';

  @override
  String get description => 'Record a video of the running Flutter app.';

  /// Transport negotiation flow:
  ///
  /// 1. **Probe** — call startScreencast (no wsPort) to discover the transport
  ///    type (TCP for native, WS for web) and viewport dimensions.
  /// 2. **Compute video size** — use the Flutter-reported frameWidth/frameHeight
  ///    as the single source of truth for ffmpeg dimensions.
  /// 3. **Start frame source** — for TCP, the Flutter app already opened a
  ///    server during the probe; for WS, the MCP side binds a WebSocket server
  ///    and passes the port back via a second startScreencast call.
  /// 4. **Record** — consume frames until duration elapses or SIGINT.
  /// 5. **Finalize** — stop session, close ffmpeg, report results.
  @override
  Future<int> execute(VmServiceConnector connector) async {
    final outputPath = argResults!['output'] as String;
    final ffmpegPath = argResults!['ffmpeg-path'] as String;
    final durationStr = argResults!['duration'] as String?;
    final widthStr = argResults!['width'] as String?;
    final heightStr = argResults!['height'] as String?;
    final shouldOpen = argResults!['open'] as bool;
    final verbose = argResults!['verbose'] as bool;

    if (!outputPath.endsWith('.webm')) {
      stderr.writeln('Error: Output file must end with .webm');
      return 1;
    }

    final transport = argResults!['transport'] as String;
    final framePortStr = argResults!['frame-port'] as String?;

    if (framePortStr != null && transport == 'ws') {
      stderr.writeln(
        'Error: --frame-port and --transport ws are mutually exclusive',
      );
      return 1;
    }

    int? framePort;
    if (framePortStr != null) {
      framePort = int.tryParse(framePortStr);
      if (framePort == null || framePort <= 0) {
        stderr.writeln('Error: --frame-port must be a positive integer');
        return 1;
      }
    }

    // Validate numeric args before any side effects.
    if ((widthStr == null) != (heightStr == null)) {
      stderr.writeln('Error: --width and --height must be specified together');
      return 1;
    }

    ({int width, int height})? explicitSize;
    if (widthStr != null && heightStr != null) {
      final w = int.tryParse(widthStr);
      final h = int.tryParse(heightStr);
      if (w == null) {
        stderr.writeln('Error: --width must be a valid integer');
        return 1;
      }
      if (h == null) {
        stderr.writeln('Error: --height must be a valid integer');
        return 1;
      }
      if (w <= 0 || h <= 0) {
        stderr.writeln('Error: --width and --height must be positive integers');
        return 1;
      }
      explicitSize = (width: w, height: h);
    }

    int? durationSeconds;
    if (durationStr != null) {
      durationSeconds = int.tryParse(durationStr);
      if (durationSeconds == null || durationSeconds <= 0) {
        stderr.writeln('Error: --duration must be a positive integer');
        return 1;
      }
    }

    if (!await _ffmpegChecker(ffmpegPath: ffmpegPath)) {
      stderr.writeln(
        'Error: ffmpeg not found at "$ffmpegPath".\n'
        'Install ffmpeg:\n'
        '  macOS:   brew install ffmpeg\n'
        '  Ubuntu:  sudo apt install ffmpeg\n'
        '  Windows: winget install ffmpeg',
      );
      return 1;
    }

    // Create output directory if needed.
    File(outputPath).parent.createSync(recursive: true);

    // Start the screencast. For TCP transport (native), the Flutter app opens
    // a TCP server and returns the port. For WS transport (web), the MCP side
    // starts a WebSocket server and passes the port to the Flutter app.
    stdout.writeln('Starting screencast...');

    // Probe to determine transport and frame dimensions.
    // When explicit size is given, send it as a bounding-box constraint.
    // Otherwise send no constraint so Flutter captures at native viewport
    // resolution (auto mode — native uses full viewport, web is capped below).
    final probeResponse = await connector.startScreencast(
      maxWidth: explicitSize?.width,
      maxHeight: explicitSize?.height,
    );
    final deviceTransport = (probeResponse['transport'] as String?) ?? 'tcp';

    // For web auto mode, apply a safe default cap. Flutter's CPU-only web
    // renderer hangs on toImage above ~1.3M pixels. 1280x720 (0.92M) is
    // well within the safe range.
    final effectiveSize =
        explicitSize ??
        (deviceTransport == 'ws'
            ? (width: webDefaultMaxWidth, height: webDefaultMaxHeight)
            : null);

    // If the probe used different constraints than we'll actually record
    // with (web auto mode), re-probe to get correct frame dimensions.
    Map<String, dynamic> response;
    if (effectiveSize != null &&
        explicitSize == null &&
        deviceTransport == 'ws') {
      response = await connector.startScreencast(
        maxWidth: effectiveSize.width,
        maxHeight: effectiveSize.height,
      );
    } else {
      response = probeResponse;
    }

    if (verbose) {
      final viewportW = response['viewportWidth'];
      final viewportH = response['viewportHeight'];
      final frameW = response['frameWidth'];
      final frameH = response['frameHeight'];
      stderr.writeln(
        '[verbose] Probe response: transport=$deviceTransport, '
        'viewport=${viewportW}x$viewportH, '
        'frame=${frameW}x$frameH, '
        'requested=${explicitSize != null ? "${explicitSize.width}x${explicitSize.height}" : "auto"}',
      );
    }

    // Fail fast if explicit dimensions exceed the viewport. The Flutter side
    // cannot upscale beyond the viewport and silently produces 0 frames.
    if (explicitSize != null && response.containsKey('viewportWidth')) {
      final viewportW = response['viewportWidth'] as int;
      final viewportH = response['viewportHeight'] as int;
      if (explicitSize.width > viewportW || explicitSize.height > viewportH) {
        // Clean up the probe's screencast before exiting.
        if (deviceTransport != 'ws') {
          await connector.stopScreencast();
        }
        stderr.writeln(
          'Error: Requested ${explicitSize.width}x${explicitSize.height} '
          'exceeds the Flutter viewport (${viewportW}x$viewportH).\n'
          'The viewport is the maximum recordable resolution.\n'
          'Either use --width $viewportW --height $viewportH, '
          'or omit --width/--height to record at native viewport size.',
        );
        return 1;
      }
    }

    // The Flutter side computes the actual frame dimensions via
    // computeFrameSize and returns them. Use these as the single source
    // of truth so ffmpeg's expected dimensions always match the frames.
    final ({int width, int height}) videoSize;
    if (response.containsKey('frameWidth')) {
      videoSize = (
        width: response['frameWidth'] as int,
        height: response['frameHeight'] as int,
      );
    } else {
      // Fallback for older Flutter-side versions that don't report frame dims.
      videoSize = effectiveSize != null
          ? validateVideoSize(size: effectiveSize)
          : validateVideoSize(
              viewportSize: (
                width: response['viewportWidth'] as int,
                height: response['viewportHeight'] as int,
              ),
            );
    }

    // For TCP, the probe actually started a screencast — stop it before
    // restarting with computed dimensions. For WS, the probe was a no-op.
    if (effectiveSize == null && deviceTransport != 'ws') {
      await connector.stopScreencast();
    }

    int? adbReversePort;
    try {
      RecordingSession session;
      if (transport == 'ws') {
        // Force WS: skip TCP, go straight to reverse-WS.
        final result = await _startReverseWsSession(
          connector: connector,
          effectiveSize: effectiveSize,
          videoSize: videoSize,
          outputPath: outputPath,
          ffmpegPath: ffmpegPath,
        );
        session = result.session;
        adbReversePort = result.adbReversePort;
      } else if (framePort != null) {
        // Explicit frame port: connect directly, no fallback.
        session = await _sessionFactory(
          frameServerPort: framePort,
          outputFile: outputPath,
          width: videoSize.width,
          height: videoSize.height,
          ffmpegPath: ffmpegPath,
        );
      } else if (deviceTransport == 'ws') {
        // Web transport: MCP hosts the WebSocket server. The probe call
        // returned transport info without actually starting the screencast,
        // so we just need one real startScreencast with wsPort.
        final wsServer = await _wsFrameServerFactory();
        await connector.startScreencast(
          maxWidth: effectiveSize?.width,
          maxHeight: effectiveSize?.height,
          wsPort: wsServer.port,
        );
        session = await _wsSessionFactory(
          frameSource: wsServer,
          outputFile: outputPath,
          width: videoSize.width,
          height: videoSize.height,
          ffmpegPath: ffmpegPath,
        );
      } else {
        // Auto or forced TCP: try TCP first.
        try {
          // TCP transport: Flutter app hosts the TCP server.
          // When explicit size was given, the probe already started the
          // screencast with the right constraints — reuse its port.
          // Otherwise the probe was stopped earlier, so start fresh.
          final int frameServerPort;
          if (explicitSize != null) {
            frameServerPort = probeResponse['port'] as int;
          } else {
            final tcpResponse = await connector.startScreencast();
            frameServerPort = tcpResponse['port'] as int;
          }
          session = await _sessionFactory(
            frameServerPort: frameServerPort,
            outputFile: outputPath,
            width: videoSize.width,
            height: videoSize.height,
            ffmpegPath: ffmpegPath,
          ).timeout(const Duration(seconds: 2));
        } on Exception {
          if (transport == 'tcp') {
            try {
              await connector.stopScreencast();
            } catch (_) {}
            stderr.writeln(
              'Error: TCP frame connection failed. The device frame port is '
              'not reachable from the host. If recording an Android device, '
              'use --transport auto to enable adb reverse fallback, or '
              'manually forward the port with '
              "'adb forward tcp:PORT tcp:PORT'.",
            );
            return 1;
          }
          // Auto mode: fall back to reverse-WS.
          final result = await _startReverseWsSession(
            connector: connector,
            effectiveSize: effectiveSize,
            videoSize: videoSize,
            outputPath: outputPath,
            ffmpegPath: ffmpegPath,
          );
          session = result.session;
          adbReversePort = result.adbReversePort;
        }
      }

      stdout.writeln(
        'Recording ${videoSize.width}x${videoSize.height} video to $outputPath...',
      );

      session.start();

      // Wait for duration or SIGINT.
      final completer = Completer<void>();
      Timer? durationTimer;

      if (durationSeconds != null) {
        durationTimer = Timer(Duration(seconds: durationSeconds), () {
          if (!completer.isCompleted) completer.complete();
        });
      }

      final sigintSub = ProcessSignal.sigint.watch().listen((_) {
        if (!completer.isCompleted) completer.complete();
      });

      stdout.writeln('Press Ctrl+C to stop recording.');
      await completer.future;
      durationTimer?.cancel();
      await sigintSub.cancel();

      // Stop and report results.
      final RecordingResult result;
      try {
        result = await session.stop();
      } on Exception catch (e) {
        stderr.writeln('Error: Recording failed during finalization: $e');
        _cleanupOutputFile(outputPath);
        return 1;
      } finally {
        await connector.stopScreencast();
        await _cleanupAdbReverse(adbReversePort);
      }
      stdout.writeln(
        'Recording complete: ${result.outputFile} '
        '(${result.duration.inSeconds}s, ${result.frameCount} frames)',
      );

      if (result.frameCount == 0 && verbose) {
        stderr.writeln(
          '[verbose] 0 frames received. Possible causes:\n'
          '  - Capture size too close to viewport (try smaller --width/--height)\n'
          '  - Flutter app not rendering (check debug console for errors)\n'
          '  - Frame capturer returning null (check Flutter debug output)',
        );
      }

      if (shouldOpen) {
        final opener = _openCommandResolver();
        if (opener != null) {
          await Process.run(opener, [outputPath]);
        } else {
          stderr.writeln('Warning: --open is not supported on this platform.');
        }
      }

      return 0;
    } on _AdbFallbackException {
      // Error already printed by _startReverseWsSession.
      try {
        await connector.stopScreencast();
      } catch (_) {}
      return 1;
    } catch (e) {
      try {
        await connector.stopScreencast();
      } catch (_) {
        // Don't mask the original error with a cleanup failure.
      }
      await _cleanupAdbReverse(adbReversePort);
      rethrow;
    }
  }

  /// Sets up a reverse-WS session: checks adb, binds a WS server, runs
  /// `adb reverse`, tears down the TCP screencast, and starts a WS screencast.
  ///
  /// Returns the session and the port used for adb reverse (for cleanup).
  /// Throws [_AdbFallbackException] if adb is unavailable or reverse fails.
  Future<_ReverseWsResult> _startReverseWsSession({
    required VmServiceConnector connector,
    required ({int width, int height})? effectiveSize,
    required ({int width, int height}) videoSize,
    required String outputPath,
    required String ffmpegPath,
  }) async {
    final adb = _adbHelperFactory();

    if (!await adb.isAvailable()) {
      stderr.writeln(
        "Error: 'adb' not found on PATH. The Android device's frame port is "
        'not directly reachable, so adb is needed to set up a reverse tunnel. '
        'Add the Android SDK platform-tools to your PATH, or specify '
        '--transport tcp with manual port forwarding.',
      );
      throw _AdbFallbackException();
    }

    final wsServer = await _wsFrameServerFactory();
    final adbResult = await adb.setupReverse(wsServer.port);
    if (!adbResult.success) {
      await wsServer.close();
      stderr.writeln(
        "Error: 'adb reverse' failed: ${adbResult.stderr}. "
        "Make sure a single device is connected (use 'adb devices' to check), "
        'or specify --transport tcp and forward the frame port manually with '
        "'adb forward tcp:PORT tcp:PORT'.",
      );
      throw _AdbFallbackException();
    }

    try {
      // Tear down the Flutter TCP server before starting WS screencast.
      await connector.stopScreencast();

      await connector.startScreencast(
        maxWidth: effectiveSize?.width,
        maxHeight: effectiveSize?.height,
        wsPort: wsServer.port,
      );

      final session = await _wsSessionFactory(
        frameSource: wsServer,
        outputFile: outputPath,
        width: videoSize.width,
        height: videoSize.height,
        ffmpegPath: ffmpegPath,
      );

      return _ReverseWsResult(session: session, adbReversePort: wsServer.port);
    } catch (_) {
      await wsServer.close();
      await _cleanupAdbReverse(wsServer.port);
      rethrow;
    }
  }

  /// Best-effort cleanup of adb reverse tunnel.
  Future<void> _cleanupAdbReverse(int? port) async {
    if (port == null) return;
    try {
      final adb = _adbHelperFactory();
      await adb.removeReverse(port);
    } catch (_) {
      // Best-effort — don't let cleanup failure mask the real error.
    }
  }

  static void _cleanupOutputFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup — don't let a delete failure mask the real error.
    }
  }

  static Future<RecordingSession> _defaultSessionFactory({
    required int frameServerPort,
    required String outputFile,
    required int width,
    required int height,
    required String ffmpegPath,
  }) async {
    final frameReader = TcpFrameReader(
      host: 'localhost',
      port: frameServerPort,
    );
    await frameReader.connect();
    return _buildSession(
      frameSource: frameReader,
      outputFile: outputFile,
      width: width,
      height: height,
      ffmpegPath: ffmpegPath,
    );
  }

  static Future<RecordingSession> _defaultWsSessionFactory({
    required FrameSource frameSource,
    required String outputFile,
    required int width,
    required int height,
    required String ffmpegPath,
  }) {
    return _buildSession(
      frameSource: frameSource,
      outputFile: outputFile,
      width: width,
      height: height,
      ffmpegPath: ffmpegPath,
    );
  }

  static Future<RecordingSession> _buildSession({
    required FrameSource frameSource,
    required String outputFile,
    required int width,
    required int height,
    required String ffmpegPath,
  }) async {
    final options = VideoOptions(
      width: width,
      height: height,
      outputFile: outputFile,
    );
    final ffmpeg = await FfmpegProcess.start(
      options: options,
      ffmpegPath: ffmpegPath,
    );
    final recorder = VideoRecorder(
      VideoRecorderOptions(fps: options.fps, width: width, height: height),
      ffmpeg,
    );
    return RecordingSession(
      frameSource: frameSource,
      videoRecorder: recorder,
      ffmpegCloseable: ffmpeg,
      outputFile: outputFile,
    );
  }

  static String? _defaultOpenCommand() {
    if (Platform.isLinux) return 'xdg-open';
    if (Platform.isMacOS) return 'open';
    if (Platform.isWindows) return 'start';
    return null;
  }
}

/// Result of [RecordVideoCommand._startReverseWsSession].
class _ReverseWsResult {
  _ReverseWsResult({required this.session, required this.adbReversePort});
  final RecordingSession session;
  final int adbReversePort;
}

/// Thrown when the ADB fallback path fails with an already-reported error.
///
/// The caller catches this to return exit code 1 without re-printing.
class _AdbFallbackException implements Exception {}
