import 'dart:async';
import 'dart:typed_data';

import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/video_recorder.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A FrameSource backed by a StreamController for test control.
class MockFrameSource implements FrameSource {
  final _controller = StreamController<SourceFrame>();

  @override
  Stream<SourceFrame> get frames => _controller.stream;

  void addFrame(Uint8List rgbaBytes, int timestampMs) {
    _controller.add(
      SourceFrame(rgbaBytes: rgbaBytes, timestampMs: timestampMs),
    );
  }

  void addError(Object error) {
    _controller.addError(error);
  }

  void done() {
    _controller.close();
  }

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

/// A FrameSource that emits N frames immediately then closes.
class FixedFrameSource implements FrameSource {
  FixedFrameSource({required this.framesToReturn});

  final int framesToReturn;
  final frameData = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

  @override
  Stream<SourceFrame> get frames async* {
    for (var i = 0; i < framesToReturn; i++) {
      yield SourceFrame(
        rgbaBytes: frameData,
        timestampMs: i * 40, // 25fps intervals
      );
    }
  }

  @override
  Future<void> close() async {}
}

class MockFfmpegCloseable implements FfmpegCloseable {
  bool closeCalled = false;

  @override
  Future<int> close() async {
    closeCalled = true;
    return 0;
  }
}

void main() {
  group('RecordingSession', () {
    group('Given a session with 5 frames available', () {
      test('When started and stopped, Then frameCount is 5', () async {
        final source = FixedFrameSource(framesToReturn: 5);
        final mockSink = MockFfmpegSink();
        final recorder = VideoRecorder(VideoRecorderOptions(fps: 25), mockSink);
        final mockFfmpeg = MockFfmpegCloseable();

        final session = RecordingSession(
          frameSource: source,
          videoRecorder: recorder,
          ffmpegCloseable: mockFfmpeg,
          outputFile: '/tmp/test.webm',
        );

        session.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final result = await session.stop();

        expect(result.frameCount, equals(5));
      });

      test('When stopped, Then ffmpegProcess.close is called', () async {
        final source = FixedFrameSource(framesToReturn: 1);
        final mockSink = MockFfmpegSink();
        final recorder = VideoRecorder(VideoRecorderOptions(fps: 25), mockSink);
        final mockFfmpeg = MockFfmpegCloseable();

        final session = RecordingSession(
          frameSource: source,
          videoRecorder: recorder,
          ffmpegCloseable: mockFfmpeg,
          outputFile: '/tmp/test.webm',
        );

        session.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await session.stop();

        expect(mockFfmpeg.closeCalled, isTrue);
      });

      test('When stopped, Then videoRecorder.stop is called', () async {
        final source = FixedFrameSource(framesToReturn: 1);
        final mockSink = MockFfmpegSink();
        final recorder = VideoRecorder(VideoRecorderOptions(fps: 25), mockSink);
        final mockFfmpeg = MockFfmpegCloseable();

        final session = RecordingSession(
          frameSource: source,
          videoRecorder: recorder,
          ffmpegCloseable: mockFfmpeg,
          outputFile: '/tmp/test.webm',
        );

        session.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await session.stop();

        expect(recorder.isStopped, isTrue);
      });

      test(
        'When stopped, Then result has correct outputFile and non-negative duration',
        () async {
          final source = FixedFrameSource(framesToReturn: 1);
          final mockSink = MockFfmpegSink();
          final recorder = VideoRecorder(
            VideoRecorderOptions(fps: 25),
            mockSink,
          );
          final mockFfmpeg = MockFfmpegCloseable();

          final session = RecordingSession(
            frameSource: source,
            videoRecorder: recorder,
            ffmpegCloseable: mockFfmpeg,
            outputFile: '/tmp/test.webm',
          );

          session.start();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final result = await session.stop();

          expect(result.outputFile, equals('/tmp/test.webm'));
          expect(result.duration.inMilliseconds, greaterThanOrEqualTo(0));
        },
      );
    });

    group('Given concurrent stop calls', () {
      test(
        'When stop() is called concurrently, Then both return the same result',
        () async {
          final source = FixedFrameSource(framesToReturn: 1);
          final mockSink = MockFfmpegSink();
          final recorder = VideoRecorder(
            VideoRecorderOptions(fps: 25),
            mockSink,
          );
          final mockFfmpeg = MockFfmpegCloseable();

          final session = RecordingSession(
            frameSource: source,
            videoRecorder: recorder,
            ffmpegCloseable: mockFfmpeg,
            outputFile: '/tmp/test.webm',
          );

          session.start();
          await Future<void>.delayed(const Duration(milliseconds: 100));

          final results = await Future.wait([session.stop(), session.stop()]);

          expect(results[0].outputFile, equals('/tmp/test.webm'));
          expect(results[1].outputFile, equals('/tmp/test.webm'));
        },
      );
    });

    group('Given a session that was never started', () {
      test(
        'When stop() is called without start(), Then it completes',
        () async {
          final source = FixedFrameSource(framesToReturn: 0);
          final mockSink = MockFfmpegSink();
          final recorder = VideoRecorder(
            VideoRecorderOptions(fps: 25),
            mockSink,
          );
          final mockFfmpeg = MockFfmpegCloseable();

          final session = RecordingSession(
            frameSource: source,
            videoRecorder: recorder,
            ffmpegCloseable: mockFfmpeg,
            outputFile: '/tmp/test.webm',
          );

          final result = await session.stop().timeout(
            const Duration(seconds: 1),
            onTimeout: () => throw StateError('stop() hung'),
          );

          expect(result.frameCount, equals(0));
        },
      );
    });

    group('Given a session that is already started', () {
      test('When start() is called again, Then it throws StateError', () {
        final source = FixedFrameSource(framesToReturn: 1);
        final mockSink = MockFfmpegSink();
        final recorder = VideoRecorder(VideoRecorderOptions(fps: 25), mockSink);
        final mockFfmpeg = MockFfmpegCloseable();

        final session = RecordingSession(
          frameSource: source,
          videoRecorder: recorder,
          ffmpegCloseable: mockFfmpeg,
          outputFile: '/tmp/test.webm',
        );

        session.start();

        expect(() => session.start(), throwsStateError);
      });
    });

    group('Given a source that emits errors', () {
      test(
        'When 10 consecutive errors, Then session auto-stops and reports disconnect',
        () async {
          final source = MockFrameSource();
          final mockSink = MockFfmpegSink();
          final recorder = VideoRecorder(
            VideoRecorderOptions(fps: 25),
            mockSink,
          );
          final mockFfmpeg = MockFfmpegCloseable();

          final session = RecordingSession(
            frameSource: source,
            videoRecorder: recorder,
            ffmpegCloseable: mockFfmpeg,
            outputFile: '/tmp/test.webm',
          );

          session.start();

          // Emit 10 errors to trigger circuit breaker.
          for (var i = 0; i < 10; i++) {
            source.addError(Exception('Connection lost'));
          }

          await Future<void>.delayed(const Duration(milliseconds: 100));
          final result = await session.stop();

          expect(result.frameCount, equals(0));
          expect(session.wasDisconnected, isTrue);
        },
      );

      test('When errors then frames, Then session recovers', () async {
        final source = MockFrameSource();
        final mockSink = MockFfmpegSink();
        final recorder = VideoRecorder(VideoRecorderOptions(fps: 25), mockSink);
        final mockFfmpeg = MockFfmpegCloseable();

        final session = RecordingSession(
          frameSource: source,
          videoRecorder: recorder,
          ffmpegCloseable: mockFfmpeg,
          outputFile: '/tmp/test.webm',
        );

        session.start();

        // Emit a few errors (fewer than circuit breaker threshold).
        for (var i = 0; i < 3; i++) {
          source.addError(Exception('Transient error'));
        }
        // Then a real frame.
        source.addFrame(Uint8List.fromList([1, 2, 3, 4]), 40);

        await Future<void>.delayed(const Duration(milliseconds: 100));
        final result = await session.stop();

        expect(result.frameCount, equals(1));
        expect(session.wasDisconnected, isFalse);
      });
    });

    group('Given a session with no frames from source', () {
      test(
        'When source closes immediately, Then session runs without error',
        () async {
          final source = FixedFrameSource(framesToReturn: 0);
          final mockSink = MockFfmpegSink();
          final recorder = VideoRecorder(
            VideoRecorderOptions(fps: 25),
            mockSink,
          );
          final mockFfmpeg = MockFfmpegCloseable();

          final session = RecordingSession(
            frameSource: source,
            videoRecorder: recorder,
            ffmpegCloseable: mockFfmpeg,
            outputFile: '/tmp/test.webm',
          );

          session.start();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final result = await session.stop();

          expect(result.frameCount, equals(0));
        },
      );
    });

    group('Given a session where ffmpeg crashes mid-recording', () {
      test('When sink throws, Then session exits gracefully', () async {
        final failingSink = FailingFfmpegSink(failAfter: 1);
        final recorder = VideoRecorder(
          VideoRecorderOptions(fps: 25),
          failingSink,
        );
        final source = MockFrameSource();
        final mockFfmpeg = MockFfmpegCloseable();

        final session = RecordingSession(
          frameSource: source,
          videoRecorder: recorder,
          ffmpegCloseable: mockFfmpeg,
          outputFile: '/tmp/test.webm',
        );

        session.start();

        // Send frames — the second will trigger gap-fill writes that fail.
        source.addFrame(Uint8List.fromList([1, 2, 3, 4]), 0);
        source.addFrame(Uint8List.fromList([5, 6, 7, 8]), 200);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final result = await session.stop().timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError('stop() hung'),
        );

        expect(recorder.hasFailed, isTrue);
        expect(result.frameCount, greaterThanOrEqualTo(1));
      });
    });

    group('Given a slow frame source', () {
      test(
        'When stop is called while frames are streaming, Then stop completes',
        () async {
          final source = MockFrameSource();
          final mockSink = MockFfmpegSink();
          final recorder = VideoRecorder(
            VideoRecorderOptions(fps: 25),
            mockSink,
          );
          final mockFfmpeg = MockFfmpegCloseable();

          final session = RecordingSession(
            frameSource: source,
            videoRecorder: recorder,
            ffmpegCloseable: mockFfmpeg,
            outputFile: '/tmp/test.webm',
          );

          session.start();
          source.addFrame(Uint8List.fromList([1, 2, 3, 4]), 0);
          await Future<void>.delayed(const Duration(milliseconds: 50));

          final result = await session.stop();
          expect(result.frameCount, equals(1));
          expect(recorder.isStopped, isTrue);
        },
      );
    });
  });
}
