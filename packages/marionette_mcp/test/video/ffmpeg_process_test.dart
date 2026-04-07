import 'dart:io';

import 'package:marionette_mcp/src/video/ffmpeg_process.dart';
import 'package:marionette_mcp/src/video/video_options.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('FfmpegProcess', () {
    group('buildArgs', () {
      late VideoOptions options;

      setUp(() {
        options = VideoOptions(
          width: 800,
          height: 600,
          outputFile: '/tmp/test.webm',
        );
      });

      test('uses rawvideo input format with rgba pixel format', () {
        final args = FfmpegProcess.buildArgs(options);
        final fIndex = args.indexOf('-f');
        expect(fIndex, isNot(-1));
        expect(args[fIndex + 1], equals('rawvideo'));

        final pixFmtIndex = args.indexOf('-pix_fmt');
        expect(pixFmtIndex, isNot(-1));
        expect(args[pixFmtIndex + 1], equals('rgba'));
      });

      test('includes input size matching video dimensions', () {
        final args = FfmpegProcess.buildArgs(options);
        final sIndex = args.indexOf('-s');
        expect(sIndex, isNot(-1));
        expect(args[sIndex + 1], equals('800x600'));
      });

      test('includes VP8 output codec', () {
        final args = FfmpegProcess.buildArgs(options);
        final codecIndex = args.indexOf('-c:v');
        expect(codecIndex, isNot(-1));
        expect(args[codecIndex + 1], equals('vp8'));
      });

      test('does not include image2pipe or png input codec', () {
        final args = FfmpegProcess.buildArgs(options);
        expect(args, isNot(contains('image2pipe')));
        // There should be no input codec flag — rawvideo is specified via -f
        // The only -c:v should be the output codec (vp8)
        final allCodecIndices = <int>[];
        for (var i = 0; i < args.length; i++) {
          if (args[i] == '-c:v') allCodecIndices.add(i);
        }
        expect(allCodecIndices, hasLength(1));
      });

      test('output file is the last argument', () {
        final args = FfmpegProcess.buildArgs(options);
        expect(args.last, equals('/tmp/test.webm'));
      });

      test('uses correct fps from options', () {
        final args = FfmpegProcess.buildArgs(options);
        final rIndex = args.indexOf('-r');
        expect(rIndex, isNot(-1));
        expect(args[rIndex + 1], equals('25'));

        final fps30Options = VideoOptions(
          width: 800,
          height: 600,
          outputFile: '/tmp/test.webm',
          fps: 30,
        );
        final args30 = FfmpegProcess.buildArgs(fps30Options);
        final rIndex30 = args30.indexOf('-r');
        expect(args30[rIndex30 + 1], equals('30'));
      });

      test('includes stdin input and no audio', () {
        final args = FfmpegProcess.buildArgs(options);
        expect(args, contains('pipe:0'));
        expect(args, contains('-an'));
      });
    });

    group('isAvailable', () {
      test('returns a bool without throwing', () async {
        final result = await FfmpegProcess.isAvailable();
        expect(result, isA<bool>());
      });
    });

    group('integration', () {
      late bool ffmpegAvailable;
      late Directory tempDir;

      setUpAll(() async {
        ffmpegAvailable = await FfmpegProcess.isAvailable();
      });

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('ffmpeg_test_');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test(
        'writing raw RGBA frames and closing produces a valid .webm file',
        () async {
          if (!ffmpegAvailable) {
            markTestSkipped('ffmpeg not available');
            return;
          }

          final outputPath = '${tempDir.path}/output.webm';
          final options = VideoOptions(
            width: 320,
            height: 240,
            outputFile: outputPath,
          );

          final process = await FfmpegProcess.start(options: options);
          addTearDown(() {
            if (!process.hasExited) process.kill();
          });

          final rgba = createTestRgba(320, 240);
          for (var i = 0; i < 10; i++) {
            process.writeFrame(rgba);
          }

          final exitCode = await process.close();
          expect(exitCode, equals(0));

          final outputFile = File(outputPath);
          expect(outputFile.existsSync(), isTrue);
          expect(outputFile.lengthSync(), greaterThan(0));
        },
      );

      test('closing with no frames exits without error', () async {
        if (!ffmpegAvailable) {
          markTestSkipped('ffmpeg not available');
          return;
        }

        final outputPath = '${tempDir.path}/empty.webm';
        final options = VideoOptions(
          width: 320,
          height: 240,
          outputFile: outputPath,
        );

        final process = await FfmpegProcess.start(options: options);
        addTearDown(() {
          if (!process.hasExited) process.kill();
        });

        // With rawvideo input, ffmpeg exits cleanly when stdin closes
        // with no data (produces an empty/minimal output file).
        final exitCode = await process.close();
        expect(exitCode, equals(0));
      });

      test('kill() terminates the process', () async {
        if (!ffmpegAvailable) {
          markTestSkipped('ffmpeg not available');
          return;
        }

        final outputPath = '${tempDir.path}/killed.webm';
        final options = VideoOptions(
          width: 320,
          height: 240,
          outputFile: outputPath,
        );

        final process = await FfmpegProcess.start(options: options);
        process.kill();

        final code = await process.exitCode;
        expect(code, isNot(0));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(process.hasExited, isTrue);
      });

      test(
        'writing many frames without awaiting each produces valid output',
        () async {
          if (!ffmpegAvailable) {
            markTestSkipped('ffmpeg not available');
            return;
          }

          final outputPath = '${tempDir.path}/batched.webm';
          final options = VideoOptions(
            width: 320,
            height: 240,
            outputFile: outputPath,
          );

          final process = await FfmpegProcess.start(options: options);
          addTearDown(() {
            if (!process.hasExited) process.kill();
          });

          final rgba = createTestRgba(320, 240);
          for (var i = 0; i < 50; i++) {
            process.writeFrame(rgba);
          }

          final exitCode = await process.close();
          expect(exitCode, equals(0));

          final outputFile = File(outputPath);
          expect(outputFile.existsSync(), isTrue);
          expect(outputFile.lengthSync(), greaterThan(0));
        },
      );

      test('close() after kill does not throw on broken stdin', () async {
        if (!ffmpegAvailable) {
          markTestSkipped('ffmpeg not available');
          return;
        }

        final outputPath = '${tempDir.path}/killed_close.webm';
        final options = VideoOptions(
          width: 320,
          height: 240,
          outputFile: outputPath,
        );

        final process = await FfmpegProcess.start(options: options);
        process.kill();
        try {
          await process.close();
        } on FfmpegException {
          // Expected — ffmpeg exited non-zero after being killed.
        }
      });

      test('writeFrame after exit throws StateError', () async {
        if (!ffmpegAvailable) {
          markTestSkipped('ffmpeg not available');
          return;
        }

        final outputPath = '${tempDir.path}/exited.webm';
        final options = VideoOptions(
          width: 320,
          height: 240,
          outputFile: outputPath,
        );

        final process = await FfmpegProcess.start(options: options);
        process.kill();
        await process.exitCode;
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final rgba = createTestRgba(320, 240);
        expect(() => process.writeFrame(rgba), throwsStateError);
      });
    });
  });
}
