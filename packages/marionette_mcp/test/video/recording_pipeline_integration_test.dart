import 'dart:io';
import 'dart:typed_data';

import 'package:marionette_mcp/src/video/ffmpeg_process.dart';
import 'package:marionette_mcp/src/video/recording_session.dart';
import 'package:marionette_mcp/src/video/video_options.dart';
import 'package:marionette_mcp/src/video/video_recorder.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A FrameSource that emits [frameCount] synthetic RGBA frames then closes.
class SyntheticFrameSource implements FrameSource {
  SyntheticFrameSource({required this.frameCount, required this.rgbaData});

  final int frameCount;
  final Uint8List rgbaData;

  @override
  Stream<SourceFrame> get frames async* {
    for (var i = 0; i < frameCount; i++) {
      yield SourceFrame(
        rgbaBytes: rgbaData,
        timestampMs: i * 40, // 25fps intervals
      );
    }
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('Recording pipeline integration', () {
    late bool ffmpegAvailable;
    late Directory tempDir;

    setUpAll(() async {
      ffmpegAvailable = await FfmpegProcess.isAvailable();
    });

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('recording_pipeline_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('produces a valid .webm file from synthetic frames', () async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg not available');
        return;
      }

      const width = 320;
      const height = 240;
      const numFrames = 10;
      final outputPath = '${tempDir.path}/output.webm';
      final rgba = createTestRgba(width, height);

      final options = VideoOptions(
        width: width,
        height: height,
        outputFile: outputPath,
      );

      final ffmpeg = await FfmpegProcess.start(options: options);
      addTearDown(() {
        if (!ffmpeg.hasExited) ffmpeg.kill();
      });

      final recorder = VideoRecorder(
        VideoRecorderOptions(fps: options.fps, width: width, height: height),
        ffmpeg,
      );

      final source = SyntheticFrameSource(
        frameCount: numFrames,
        rgbaData: rgba,
      );

      final session = RecordingSession(
        frameSource: source,
        videoRecorder: recorder,
        ffmpegCloseable: ffmpeg,
        outputFile: outputPath,
      );

      session.start();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final result = await session.stop();

      // Output file exists and is non-empty.
      final outputFile = File(outputPath);
      expect(outputFile.existsSync(), isTrue);
      expect(outputFile.lengthSync(), greaterThan(0));

      // File starts with WebM magic bytes.
      final bytes = outputFile.readAsBytesSync();
      expect(bytes.sublist(0, 4), equals([0x1A, 0x45, 0xDF, 0xA3]));

      // Result metadata is correct.
      expect(result.frameCount, equals(numFrames));
      expect(result.duration.inMilliseconds, greaterThan(0));
      expect(result.outputFile, equals(outputPath));
    });

    test('handles zero frames gracefully (synthetic white frame)', () async {
      if (!ffmpegAvailable) {
        markTestSkipped('ffmpeg not available');
        return;
      }

      const width = 320;
      const height = 240;
      final outputPath = '${tempDir.path}/zero_frames.webm';

      final options = VideoOptions(
        width: width,
        height: height,
        outputFile: outputPath,
      );

      final ffmpeg = await FfmpegProcess.start(options: options);
      addTearDown(() {
        if (!ffmpeg.hasExited) ffmpeg.kill();
      });

      final recorder = VideoRecorder(
        VideoRecorderOptions(fps: options.fps, width: width, height: height),
        ffmpeg,
      );

      final source = SyntheticFrameSource(
        frameCount: 0,
        rgbaData: Uint8List(0),
      );

      final session = RecordingSession(
        frameSource: source,
        videoRecorder: recorder,
        ffmpegCloseable: ffmpeg,
        outputFile: outputPath,
      );

      session.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final result = await session.stop();

      // Output file exists (VideoRecorder writes a synthetic white frame).
      final outputFile = File(outputPath);
      expect(outputFile.existsSync(), isTrue);
      expect(outputFile.lengthSync(), greaterThan(0));

      // File starts with WebM magic bytes.
      final bytes = outputFile.readAsBytesSync();
      expect(bytes.sublist(0, 4), equals([0x1A, 0x45, 0xDF, 0xA3]));

      // No real frames were delivered.
      expect(result.frameCount, equals(0));
    });
  });
}
