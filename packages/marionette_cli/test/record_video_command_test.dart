import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/args.dart';
import 'package:marionette_cli/src/cli/adb_helper.dart';
import 'package:marionette_cli/src/cli/commands/record_video_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/video/ffmpeg_process.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/ws_frame_server.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:test/test.dart';

/// Mirrors ScreencastService.computeFrameSize for mock connectors.
///
/// This must stay in sync with the real implementation in
/// `marionette_flutter/lib/src/services/screencast_service.dart`.
/// The CLI test package cannot depend on marionette_flutter (which
/// requires the Flutter SDK), so this is duplicated here.
(int, int) _computeFrameSize(int w, int h, int? maxW, int? maxH) {
  if (maxW == null || maxH == null) {
    return (math.max(2, w & ~1), math.max(2, h & ~1));
  }
  if (w <= maxW && h <= maxH) {
    return (math.max(2, w & ~1), math.max(2, h & ~1));
  }
  final scale = math.min(maxW / w, maxH / h);
  return (
    math.max(2, (w * scale).floor() & ~1),
    math.max(2, (h * scale).floor() & ~1),
  );
}

/// A mock connector that throws if any method is called.
class MockConnector implements VmServiceConnector {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Records a single startScreencast call's arguments.
class StartScreencastCall {
  StartScreencastCall({this.maxWidth, this.maxHeight, this.wsPort});
  final int? maxWidth;
  final int? maxHeight;
  final int? wsPort;
}

/// A mock connector that tracks screencast calls and returns canned responses.
class RecordingMockConnector implements VmServiceConnector {
  int stopScreencastCallCount = 0;

  final startScreencastCalls = <StartScreencastCall>[];

  int get startScreencastCallCount => startScreencastCalls.length;
  int? get lastMaxWidth => startScreencastCalls.lastOrNull?.maxWidth;
  int? get lastMaxHeight => startScreencastCalls.lastOrNull?.maxHeight;

  /// Viewport dimensions to return from startScreencast.
  int viewportWidth = 800;
  int viewportHeight = 600;

  /// TCP port to return from startScreencast.
  int port = 12345;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    startScreencastCalls.add(
      StartScreencastCall(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        wsPort: wsPort,
      ),
    );
    final (frameW, frameH) = _computeFrameSize(
      viewportWidth,
      viewportHeight,
      maxWidth,
      maxHeight,
    );
    return {
      'transport': 'tcp',
      'viewportWidth': viewportWidth,
      'viewportHeight': viewportHeight,
      'frameWidth': frameW,
      'frameHeight': frameH,
      'port': port,
    };
  }

  @override
  Future<Map<String, dynamic>> stopScreencast() async {
    stopScreencastCallCount++;
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A mock RecordingSession that completes immediately on stop.
class MockRecordingSession implements RecordingSession {
  bool startCalled = false;
  bool stopCalled = false;
  int frameCount;
  Duration duration;

  MockRecordingSession({
    this.frameCount = 10,
    this.duration = const Duration(seconds: 2),
  });

  @override
  void start() {
    startCalled = true;
  }

  @override
  Future<RecordingResult> stop() async {
    stopCalled = true;
    return RecordingResult(
      outputFile: '/tmp/test.webm',
      duration: duration,
      frameCount: frameCount,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A testable subclass that overrides argResults so we can call execute()
/// directly without going through the full CommandRunner connection flow.
class TestableRecordVideoCommand extends RecordVideoCommand {
  TestableRecordVideoCommand({
    FfmpegAvailabilityChecker? ffmpegChecker,
    RecordingSessionFactory? sessionFactory,
    WsRecordingSessionFactory? wsSessionFactory,
    WsFrameServerFactory? wsFrameServerFactory,
    OpenCommandResolver? openCommandResolver,
    AdbHelperFactory? adbHelperFactory,
  }) : super(
         InstanceRegistry(),
         ffmpegChecker: ffmpegChecker,
         sessionFactory: sessionFactory,
         wsSessionFactory: wsSessionFactory,
         wsFrameServerFactory: wsFrameServerFactory,
         openCommandResolver: openCommandResolver,
         adbHelperFactory: adbHelperFactory,
       );

  ArgResults? _overriddenArgResults;

  @override
  ArgResults? get argResults => _overriddenArgResults;

  /// Parses [args] on this command's argParser, then calls execute().
  Future<int> executeWithArgs(
    List<String> args,
    VmServiceConnector connector,
  ) async {
    _overriddenArgResults = argParser.parse(args);
    return execute(connector);
  }
}

RecordingSessionFactory _mockSessionFactory(MockRecordingSession session) {
  return ({
    required int frameServerPort,
    required String outputFile,
    required int width,
    required int height,
    required String ffmpegPath,
  }) async => session;
}

void main() {
  late RecordVideoCommand command;

  setUp(() {
    final registry = InstanceRegistry();
    command = RecordVideoCommand(registry);
  });

  group('RecordVideoCommand', () {
    group('Given a command instance', () {
      test('When checking name, Then it is record-video', () {
        expect(command.name, equals('record-video'));
      });

      test('When checking description, Then it is non-empty', () {
        expect(command.description, isNotEmpty);
      });
    });

    group('Given argument parsing', () {
      test('When --output is defined, Then it is mandatory', () {
        final option = command.argParser.options['output']!;
        expect(option.mandatory, isTrue);
      });

      test('When --output is provided, Then it is parsed correctly', () {
        final results = command.argParser.parse(['-o', 'recording.webm']);
        expect(results['output'], equals('recording.webm'));
      });
    });

    group('Given output validation', () {
      test(
        'When output does not end with .webm, Then returns exit code 1',
        () async {
          final testCommand = TestableRecordVideoCommand();
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            'test.mp4',
          ], MockConnector());
          expect(exitCode, equals(1));
        },
      );
    });

    group('Given --ffmpeg-path option', () {
      test('When omitted, Then it defaults to ffmpeg', () {
        final results = command.argParser.parse(['-o', 'recording.webm']);
        expect(results['ffmpeg-path'], equals('ffmpeg'));
      });

      test('When provided, Then it uses the given path', () {
        final results = command.argParser.parse([
          '-o',
          'recording.webm',
          '--ffmpeg-path',
          '/usr/local/bin/ffmpeg',
        ]);
        expect(results['ffmpeg-path'], equals('/usr/local/bin/ffmpeg'));
      });
    });

    group('Given --open flag', () {
      test('When --open is provided, Then it is true', () {
        final results = command.argParser.parse([
          '-o',
          'recording.webm',
          '--open',
        ]);
        expect(results['open'], isTrue);
      });

      test('When --open is omitted, Then it defaults to false', () {
        final results = command.argParser.parse(['-o', 'recording.webm']);
        expect(results['open'], isFalse);
      });
    });

    group('Given duration option', () {
      test('When --duration is provided, Then it parses correctly', () {
        final results = command.argParser.parse([
          '-o',
          'recording.webm',
          '-d',
          '10',
        ]);
        expect(results['duration'], equals('10'));
      });

      test('When --duration is omitted, Then it is null', () {
        final results = command.argParser.parse(['-o', 'recording.webm']);
        expect(results['duration'], isNull);
      });
    });

    group('Given dimension options', () {
      test(
        'When --width and --height are provided, Then they parse correctly',
        () {
          final results = command.argParser.parse([
            '-o',
            'recording.webm',
            '--width',
            '640',
            '--height',
            '480',
          ]);
          expect(results['width'], equals('640'));
          expect(results['height'], equals('480'));
        },
      );

      test('When --width and --height are omitted, Then they are null', () {
        final results = command.argParser.parse(['-o', 'recording.webm']);
        expect(results['width'], isNull);
        expect(results['height'], isNull);
      });
    });

    group('Given ffmpeg availability', () {
      test('When ffmpeg is not available, Then returns exit code 1', () async {
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => false,
        );
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          'test.webm',
        ], MockConnector());
        expect(exitCode, equals(1));
      });
    });

    group('Given --width/--height pairing validation', () {
      test(
        'When --width is provided without --height, Then returns exit code 1',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '--width',
            '640',
          ], MockConnector());
          expect(exitCode, equals(1));
        },
      );

      test(
        'When --height is provided without --width, Then returns exit code 1',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '--height',
            '480',
          ], MockConnector());
          expect(exitCode, equals(1));
        },
      );
    });

    group('Given numeric argument validation', () {
      test('When --width is non-numeric, Then returns exit code 1', () async {
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
        );
        final connector = RecordingMockConnector();
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '--width',
          'abc',
          '--height',
          '480',
        ], connector);
        expect(exitCode, equals(1));
      });

      test('When --height is non-numeric, Then returns exit code 1', () async {
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
        );
        final connector = RecordingMockConnector();
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '--width',
          '640',
          '--height',
          'abc',
        ], connector);
        expect(exitCode, equals(1));
      });
      test('When --width is 0, Then returns exit code 1', () async {
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
        );
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '--width',
          '0',
          '--height',
          '0',
        ], MockConnector());
        expect(exitCode, equals(1));
      });

      test('When --width is negative, Then returns exit code 1', () async {
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
        );
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '--width',
          '-1',
          '--height',
          '-1',
        ], MockConnector());
        expect(exitCode, equals(1));
      });

      test(
        'When --duration is non-numeric, Then returns exit code 1',
        () async {
          final mockSession = MockRecordingSession();
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _mockSessionFactory(mockSession),
          );
          final connector = RecordingMockConnector();
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            'abc',
          ], connector);
          expect(exitCode, equals(1));
        },
      );
    });

    group('Given screencast cleanup on failure', () {
      test(
        'When session factory throws after startScreencast, Then stopScreencast is called',
        () async {
          final connector = RecordingMockConnector();
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory:
                ({
                  required int frameServerPort,
                  required String outputFile,
                  required int width,
                  required int height,
                  required String ffmpegPath,
                }) async {
                  throw Exception('ffmpeg failed to start');
                },
          );
          // Should throw but also clean up screencast.
          // Use --transport tcp to avoid triggering auto-fallback to WS.
          try {
            await testCommand.executeWithArgs([
              '-o',
              '/tmp/test.webm',
              '-d',
              '1',
              '--transport',
              'tcp',
            ], connector);
          } catch (_) {}
          // stopScreencast is called twice: once during probe cleanup
          // (no explicit size), and again on the TCP failure error path.
          expect(connector.stopScreencastCallCount, equals(2));
        },
      );
    });

    group('Given --open on unsupported platform', () {
      test('When opener returns null, Then prints warning to stderr', () async {
        final connector = RecordingMockConnector();
        final mockSession = MockRecordingSession();
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
          sessionFactory: _mockSessionFactory(mockSession),
          openCommandResolver: () => null,
        );
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '-d',
          '1',
          '--open',
        ], connector);
        expect(exitCode, equals(0));
      });
    });

    group('Given recording execution', () {
      late RecordingMockConnector connector;
      late MockRecordingSession mockSession;

      TestableRecordVideoCommand createCommand({
        MockRecordingSession? session,
      }) {
        mockSession = session ?? MockRecordingSession();
        return TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
          sessionFactory: _mockSessionFactory(mockSession),
        );
      }

      setUp(() {
        connector = RecordingMockConnector();
      });

      test(
        'When executed without explicit size, Then starts screencast twice (probe + constrained)',
        () async {
          final testCommand = createCommand();
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          expect(connector.startScreencastCallCount, equals(2));
        },
      );

      test(
        'When no explicit size, Then startScreencast sends no bounding constraint (auto mode)',
        () async {
          connector.viewportWidth = 1920;
          connector.viewportHeight = 1080;
          final testCommand = createCommand();
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          // Auto mode: no bounding box sent, so Flutter captures at native
          // viewport resolution.
          expect(connector.startScreencastCalls.first.maxWidth, isNull);
          expect(connector.startScreencastCalls.first.maxHeight, isNull);
        },
      );

      test(
        'When viewport is 1920x1080, Then session gets native viewport dimensions',
        () async {
          connector.viewportWidth = 1920;
          connector.viewportHeight = 1080;
          int? receivedWidth;
          int? receivedHeight;
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory:
                ({
                  required int frameServerPort,
                  required String outputFile,
                  required int width,
                  required int height,
                  required String ffmpegPath,
                }) async {
                  receivedWidth = width;
                  receivedHeight = height;
                  return MockRecordingSession();
                },
          );
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          // Auto mode: no bounding box, so Flutter returns native viewport
          // dimensions (even-aligned).
          expect(receivedWidth, equals(1920));
          expect(receivedHeight, equals(1080));
        },
      );

      test(
        'When executed with --duration, Then session start and stop are called',
        () async {
          final testCommand = createCommand();
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          expect(mockSession.startCalled, isTrue);
          expect(mockSession.stopCalled, isTrue);
        },
      );

      test('When executed, Then returns exit code 0', () async {
        final testCommand = createCommand();
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '-d',
          '1',
        ], connector);
        expect(exitCode, equals(0));
      });

      test(
        'When --width and --height provided, Then startScreencast is called once with those constraints',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _mockSessionFactory(MockRecordingSession()),
          );
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--width',
            '640',
            '--height',
            '480',
          ], connector);
          expect(connector.startScreencastCallCount, equals(1));
          expect(connector.lastMaxWidth, equals(640));
          expect(connector.lastMaxHeight, equals(480));
        },
      );

      test(
        'When --width and --height provided, Then session factory receives those dimensions',
        () async {
          int? receivedWidth;
          int? receivedHeight;
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory:
                ({
                  required int frameServerPort,
                  required String outputFile,
                  required int width,
                  required int height,
                  required String ffmpegPath,
                }) async {
                  receivedWidth = width;
                  receivedHeight = height;
                  return MockRecordingSession();
                },
          );
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--width',
            '640',
            '--height',
            '480',
          ], connector);
          expect(receivedWidth, equals(640));
          expect(receivedHeight, equals(480));
        },
      );

      test(
        'When session factory receives the frame server port from startScreencast',
        () async {
          connector.port = 54321;
          int? receivedPort;
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory:
                ({
                  required int frameServerPort,
                  required String outputFile,
                  required int width,
                  required int height,
                  required String ffmpegPath,
                }) async {
                  receivedPort = frameServerPort;
                  return MockRecordingSession();
                },
          );
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--width',
            '640',
            '--height',
            '480',
          ], connector);
          expect(receivedPort, equals(54321));
        },
      );
    });

    group('Given explicit size exceeds viewport', () {
      late RecordingMockConnector connector;

      setUp(() {
        connector = RecordingMockConnector();
        connector.viewportWidth = 1632;
        connector.viewportHeight = 798;
      });

      test(
        'When requested width exceeds viewport, Then returns exit code 1',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _mockSessionFactory(MockRecordingSession()),
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--width',
            '1920',
            '--height',
            '798',
          ], connector);
          expect(exitCode, equals(1));
        },
      );

      test(
        'When requested height exceeds viewport, Then returns exit code 1',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _mockSessionFactory(MockRecordingSession()),
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--width',
            '1632',
            '--height',
            '1080',
          ], connector);
          expect(exitCode, equals(1));
        },
      );

      test(
        'When requested size fits within viewport, Then returns exit code 0',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _mockSessionFactory(MockRecordingSession()),
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--width',
            '1632',
            '--height',
            '798',
          ], connector);
          expect(exitCode, equals(0));
        },
      );
    });

    group('Given session.stop() throws FfmpegException', () {
      test('When ffmpeg fails during stop, Then returns exit code 1', () async {
        final connector = RecordingMockConnector();
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
          sessionFactory:
              ({
                required int frameServerPort,
                required String outputFile,
                required int width,
                required int height,
                required String ffmpegPath,
              }) async => FailingStopSession(),
        );
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '-d',
          '1',
        ], connector);
        expect(exitCode, equals(1));
      });

      test(
        'When ffmpeg fails during stop, Then output file is cleaned up',
        () async {
          final tempDir = Directory.systemTemp.createTempSync('record_test_');
          addTearDown(() => tempDir.deleteSync(recursive: true));
          final outputPath = '${tempDir.path}/output.webm';

          File(outputPath).writeAsStringSync('partial data');
          expect(File(outputPath).existsSync(), isTrue);

          final connector = RecordingMockConnector();
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory:
                ({
                  required int frameServerPort,
                  required String outputFile,
                  required int width,
                  required int height,
                  required String ffmpegPath,
                }) async => FailingStopSession(),
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            outputPath,
            '-d',
            '1',
          ], connector);
          expect(exitCode, equals(1));
          expect(File(outputPath).existsSync(), isFalse);
        },
      );
    });

    group('Given --transport option', () {
      test('When omitted, Then defaults to auto', () {
        final results = command.argParser.parse(['-o', 'recording.webm']);
        expect(results['transport'], equals('auto'));
      });

      test('When set to ws, Then parses correctly', () {
        final results = command.argParser.parse([
          '-o',
          'recording.webm',
          '--transport',
          'ws',
        ]);
        expect(results['transport'], equals('ws'));
      });

      test('When set to tcp, Then parses correctly', () {
        final results = command.argParser.parse([
          '-o',
          'recording.webm',
          '--transport',
          'tcp',
        ]);
        expect(results['transport'], equals('tcp'));
      });
    });

    group('Given --frame-port option', () {
      test('When provided, Then parses correctly', () {
        final results = command.argParser.parse([
          '-o',
          'recording.webm',
          '--frame-port',
          '9999',
        ]);
        expect(results['frame-port'], equals('9999'));
      });

      test('When omitted, Then is null', () {
        final results = command.argParser.parse(['-o', 'recording.webm']);
        expect(results['frame-port'], isNull);
      });
    });

    group('Given --frame-port and --transport ws conflict', () {
      test('When both provided, Then returns exit code 1', () async {
        final testCommand = TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
        );
        // MockConnector is safe here because validation exits before any
        // connector methods are called.
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '--frame-port',
          '9999',
          '--transport',
          'ws',
        ], MockConnector());
        expect(exitCode, equals(1));
      });
    });

    group('Given WS transport', () {
      late WsMockConnector connector;
      late FakeWsFrameServer fakeWsServer;
      late MockRecordingSession mockSession;

      setUp(() {
        connector = WsMockConnector();
        fakeWsServer = FakeWsFrameServer(port: 54321);
        mockSession = MockRecordingSession();
      });

      TestableRecordVideoCommand createWsCommand({
        MockRecordingSession? session,
      }) {
        final s = session ?? mockSession;
        return TestableRecordVideoCommand(
          ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
          sessionFactory: _mockSessionFactory(s),
          wsSessionFactory:
              ({
                required FrameSource frameSource,
                required String outputFile,
                required int width,
                required int height,
                required String ffmpegPath,
              }) async => s,
          wsFrameServerFactory: () async => fakeWsServer,
        );
      }

      test(
        'When transport is ws, Then wsPort is passed to startScreencast',
        () async {
          final testCommand = createWsCommand();
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--width',
            '640',
            '--height',
            '480',
          ], connector);
          // Probe call has no wsPort, restart call has wsPort.
          expect(connector.startScreencastCallCount, equals(2));
          expect(connector.startScreencastCalls.last.wsPort, equals(54321));
        },
      );

      test(
        'When transport is ws without explicit size, Then probe + re-probe with web cap + start with wsPort',
        () async {
          final testCommand = createWsCommand();
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          // Probe (no constraint) + re-probe (1280x720 web cap) + start with wsPort.
          // No stopScreencast between calls — web probes are no-ops.
          // One stopScreencast at the end of recording to reset state.
          expect(connector.startScreencastCallCount, equals(3));
          expect(connector.startScreencastCalls[0].maxWidth, isNull);
          expect(connector.startScreencastCalls[0].wsPort, isNull);
          expect(connector.startScreencastCalls[1].maxWidth, equals(1280));
          expect(connector.startScreencastCalls[1].maxHeight, equals(720));
          expect(connector.startScreencastCalls[1].wsPort, isNull);
          expect(connector.startScreencastCalls[2].maxWidth, equals(1280));
          expect(connector.startScreencastCalls[2].maxHeight, equals(720));
          expect(connector.startScreencastCalls[2].wsPort, equals(54321));
          expect(connector.stopScreencastCallCount, equals(1));
        },
      );

      test(
        'When transport is ws, Then session is started and stopped',
        () async {
          final testCommand = createWsCommand();
          await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          expect(mockSession.startCalled, isTrue);
          expect(mockSession.stopCalled, isTrue);
        },
      );

      test('When transport is ws, Then returns exit code 0', () async {
        final testCommand = createWsCommand();
        final exitCode = await testCommand.executeWithArgs([
          '-o',
          '/tmp/test.webm',
          '-d',
          '1',
        ], connector);
        expect(exitCode, equals(0));
      });
    });

    group('Given TCP connection fails (Android fallback)', () {
      late FallbackMockConnector connector;
      late FakeWsFrameServer fakeWsServer;
      late MockRecordingSession mockSession;

      setUp(() {
        connector = FallbackMockConnector();
        fakeWsServer = FakeWsFrameServer(port: 54321);
        mockSession = MockRecordingSession();
      });

      WsRecordingSessionFactory _mockWsSessionFactory(
        MockRecordingSession session,
      ) {
        return ({
          required FrameSource frameSource,
          required String outputFile,
          required int width,
          required int height,
          required String ffmpegPath,
        }) async => session;
      }

      test(
        'When auto fallback succeeds, Then adb reverse called, WS session used, cleanup on exit',
        () async {
          final adbHelper = MockAdbHelperAvailable();
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _failingTcpSessionFactory(),
            wsSessionFactory: _mockWsSessionFactory(mockSession),
            wsFrameServerFactory: () async => fakeWsServer,
            adbHelperFactory: () => adbHelper,
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          expect(exitCode, equals(0));
          expect(adbHelper.setupReverseCalled, isTrue);
          expect(adbHelper.setupReversePort, equals(fakeWsServer.port));
          expect(adbHelper.removeReverseCalled, isTrue);
          expect(adbHelper.removeReversePort, equals(fakeWsServer.port));
          // Verify startScreencast was called with wsPort for the WS session.
          final wsCalls = connector.startScreencastCalls
              .where((c) => c.wsPort != null)
              .toList();
          expect(wsCalls, hasLength(1));
          expect(wsCalls.first.wsPort, equals(fakeWsServer.port));
          expect(mockSession.startCalled, isTrue);
          expect(mockSession.stopCalled, isTrue);
        },
      );

      test(
        'When auto fallback and adb unavailable, Then returns exit code 1 with actionable error',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _failingTcpSessionFactory(),
            wsFrameServerFactory: () async => fakeWsServer,
            adbHelperFactory: () => MockAdbHelperUnavailable(),
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          expect(exitCode, equals(1));
        },
      );

      test(
        'When auto fallback and adb reverse fails, Then returns exit code 1 with actionable error',
        () async {
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _failingTcpSessionFactory(),
            wsFrameServerFactory: () async => fakeWsServer,
            adbHelperFactory: () => MockAdbHelperSetupFails(),
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
          ], connector);
          expect(exitCode, equals(1));
        },
      );

      test(
        'When --transport tcp forces TCP and TCP fails, Then no fallback attempted, exit code 1',
        () async {
          final adbHelper = MockAdbHelperAvailable();
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _failingTcpSessionFactory(),
            wsFrameServerFactory: () async => fakeWsServer,
            adbHelperFactory: () => adbHelper,
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--transport',
            'tcp',
          ], connector);
          expect(exitCode, equals(1));
          // No adb operations should have been attempted.
          expect(adbHelper.setupReverseCalled, isFalse);
        },
      );

      test(
        'When --transport ws forces WS, Then TCP attempt skipped, WS path used directly, exit code 0',
        () async {
          final adbHelper = MockAdbHelperAvailable();
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory: _failingTcpSessionFactory(),
            wsSessionFactory: _mockWsSessionFactory(mockSession),
            wsFrameServerFactory: () async => fakeWsServer,
            adbHelperFactory: () => adbHelper,
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--transport',
            'ws',
          ], connector);
          expect(exitCode, equals(0));
          // adb reverse should be called for forced WS on a TCP device.
          expect(adbHelper.setupReverseCalled, isTrue);
          expect(mockSession.startCalled, isTrue);
        },
      );

      test(
        'When --frame-port overrides, Then session factory receives specified port, no adb reverse called',
        () async {
          final adbHelper = MockAdbHelperAvailable();
          int? receivedPort;
          final testCommand = TestableRecordVideoCommand(
            ffmpegChecker: ({String ffmpegPath = 'ffmpeg'}) async => true,
            sessionFactory:
                ({
                  required int frameServerPort,
                  required String outputFile,
                  required int width,
                  required int height,
                  required String ffmpegPath,
                }) async {
                  receivedPort = frameServerPort;
                  return mockSession;
                },
            adbHelperFactory: () => adbHelper,
          );
          final exitCode = await testCommand.executeWithArgs([
            '-o',
            '/tmp/test.webm',
            '-d',
            '1',
            '--frame-port',
            '9999',
          ], connector);
          expect(exitCode, equals(0));
          expect(receivedPort, equals(9999));
          expect(adbHelper.setupReverseCalled, isFalse);
        },
      );
    });
  });
}

/// A mock session whose stop() throws FfmpegException (simulating ffmpeg crash).
class FailingStopSession implements RecordingSession {
  @override
  void start() {}

  @override
  Future<RecordingResult> stop() async {
    throw FfmpegException('ffmpeg exited with code 1: pipe broken');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A mock connector that returns 'ws' transport.
class WsMockConnector implements VmServiceConnector {
  int stopScreencastCallCount = 0;
  final startScreencastCalls = <StartScreencastCall>[];

  int get startScreencastCallCount => startScreencastCalls.length;
  int? get lastWsPort => startScreencastCalls.lastOrNull?.wsPort;

  int viewportWidth = 800;
  int viewportHeight = 600;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    startScreencastCalls.add(
      StartScreencastCall(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        wsPort: wsPort,
      ),
    );
    final (frameW, frameH) = _computeFrameSize(
      viewportWidth,
      viewportHeight,
      maxWidth,
      maxHeight,
    );
    return {
      'transport': 'ws',
      'viewportWidth': viewportWidth,
      'viewportHeight': viewportHeight,
      'frameWidth': frameW,
      'frameHeight': frameH,
    };
  }

  @override
  Future<Map<String, dynamic>> stopScreencast() async {
    stopScreencastCallCount++;
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A fake WebSocketFrameServer for testing the WS transport path.
class FakeWsFrameServer implements WebSocketFrameServer {
  FakeWsFrameServer({this.port = 54321});

  @override
  final int port;

  @override
  Stream<SourceFrame> get frames => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> start() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A mock AdbHelper where adb is available and all operations succeed.
class MockAdbHelperAvailable implements AdbHelper {
  bool setupReverseCalled = false;
  bool removeReverseCalled = false;
  int? setupReversePort;
  int? removeReversePort;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AdbResult> setupReverse(int port) async {
    setupReverseCalled = true;
    setupReversePort = port;
    return const AdbResult(success: true);
  }

  @override
  Future<AdbResult> removeReverse(int port) async {
    removeReverseCalled = true;
    removeReversePort = port;
    return const AdbResult(success: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A mock AdbHelper where adb is not available.
class MockAdbHelperUnavailable implements AdbHelper {
  @override
  Future<bool> isAvailable() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A mock AdbHelper where adb is available but setupReverse fails.
class MockAdbHelperSetupFails implements AdbHelper {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<AdbResult> setupReverse(int port) async {
    return const AdbResult(
      success: false,
      stderr: 'error: more than one device/emulator',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A mock connector that returns TCP transport on probe but supports
/// WS fallback via startScreencast(wsPort: ...).
class FallbackMockConnector implements VmServiceConnector {
  int stopScreencastCallCount = 0;
  final startScreencastCalls = <StartScreencastCall>[];

  int get startScreencastCallCount => startScreencastCalls.length;

  int viewportWidth = 800;
  int viewportHeight = 600;
  int port = 12345;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async {
    startScreencastCalls.add(
      StartScreencastCall(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        wsPort: wsPort,
      ),
    );
    final (frameW, frameH) = _computeFrameSize(
      viewportWidth,
      viewportHeight,
      maxWidth,
      maxHeight,
    );
    return {
      'transport': 'tcp',
      'viewportWidth': viewportWidth,
      'viewportHeight': viewportHeight,
      'frameWidth': frameW,
      'frameHeight': frameH,
      'port': port,
    };
  }

  @override
  Future<Map<String, dynamic>> stopScreencast() async {
    stopScreencastCallCount++;
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A TCP session factory that throws SocketException, simulating
/// TcpFrameReader.connect() failing (e.g. Android device not reachable).
RecordingSessionFactory _failingTcpSessionFactory() {
  return ({
    required int frameServerPort,
    required String outputFile,
    required int width,
    required int height,
    required String ffmpegPath,
  }) async {
    throw const SocketException('Connection refused');
  };
}
