import 'dart:typed_data';

import 'package:marionette_mcp/src/video/video_recorder.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A sink that throws a non-StateError exception on first write.
class IoExceptionSink implements FfmpegSink {
  @override
  void writeFrame(Uint8List data) {
    throw Exception('Broken pipe');
  }
}

void main() {
  group('VideoRecorder', () {
    late MockFfmpegSink mockSink;
    late VideoRecorder recorder;

    final frame1 = Uint8List.fromList([1, 2, 3]);

    setUp(() {
      mockSink = MockFfmpegSink();
    });

    group('Given a new recorder', () {
      setUp(() {
        recorder = VideoRecorder(VideoRecorderOptions(fps: 25), mockSink);
      });

      test(
        'When first frame is written, Then nothing is sent to ffmpeg',
        () async {
          recorder.writeFrame(frame1, 0.0);

          expect(mockSink.writtenFrames, isEmpty);
        },
      );

      test(
        'When second frame arrives at t=0.2, Then first frame is repeated 5 times',
        () async {
          final frame2 = Uint8List.fromList([4, 5, 6]);

          recorder.writeFrame(frame1, 0.0);
          recorder.writeFrame(frame2, 0.2);

          expect(mockSink.writtenFrames, hasLength(5));
          for (final frame in mockSink.writtenFrames) {
            expect(frame, equals(frame1));
          }
        },
      );

      test('When one-second gap, Then 25 frames are repeated', () async {
        final frame2 = Uint8List.fromList([4, 5, 6]);

        recorder.writeFrame(frame1, 0.0);
        recorder.writeFrame(frame2, 1.0);

        expect(mockSink.writtenFrames, hasLength(25));
      });

      test('When same timestamp, Then zero repeats', () async {
        final frame2 = Uint8List.fromList([4, 5, 6]);

        recorder.writeFrame(frame1, 0.0);
        recorder.writeFrame(frame2, 0.0);

        expect(mockSink.writtenFrames, isEmpty);
      });

      test(
        'When three sequential frames, Then gaps filled correctly',
        () async {
          final frame2 = Uint8List.fromList([4, 5, 6]);
          final frame3 = Uint8List.fromList([7, 8, 9]);

          recorder.writeFrame(frame1, 0.0);
          recorder.writeFrame(frame2, 0.2);
          recorder.writeFrame(frame3, 0.4);

          expect(mockSink.writtenFrames, hasLength(10));
          // First 5 are frame1 (gap from frame 0 to frame 5)
          for (var i = 0; i < 5; i++) {
            expect(mockSink.writtenFrames[i], equals(frame1));
          }
          // Next 5 are frame2 (gap from frame 5 to frame 10)
          for (var i = 5; i < 10; i++) {
            expect(mockSink.writtenFrames[i], equals(frame2));
          }
        },
      );

      test('When 5-second gap, Then 125 frames are repeated', () async {
        final frame2 = Uint8List.fromList([4, 5, 6]);

        recorder.writeFrame(frame1, 0.0);
        recorder.writeFrame(frame2, 5.0);

        expect(mockSink.writtenFrames, hasLength(125));
      });

      test(
        'When stop with no frames, Then writes synthetic white frame to ffmpeg',
        () async {
          recorder.stop();

          expect(mockSink.writtenFrames, isNotEmpty);
          // Should have written at least 25 frames (1 second padding of the synthetic frame)
          expect(mockSink.writtenFrames.length, greaterThanOrEqualTo(25));
        },
      );

      test(
        'When stop after two frames, Then pads with at least 25 frames',
        () async {
          final frame2 = Uint8List.fromList([4, 5, 6]);

          recorder.writeFrame(frame1, 0.0);
          recorder.writeFrame(frame2, 0.04); // 1 frame later
          recorder.stop();

          // 1 frame of frame1 (gap from 0 to 1) + at least 25 frames of frame2 padding
          expect(mockSink.writtenFrames.length, greaterThanOrEqualTo(26));
        },
      );

      test(
        'When writeFrame after stop, Then it is silently discarded',
        () async {
          final frame2 = Uint8List.fromList([4, 5, 6]);
          final frame3 = Uint8List.fromList([7, 8, 9]);

          recorder.writeFrame(frame1, 0.0);
          recorder.writeFrame(frame2, 0.04);
          recorder.stop();

          final countAfterStop = mockSink.writtenFrames.length;
          recorder.writeFrame(frame3, 2.0);

          expect(mockSink.writtenFrames.length, equals(countAfterStop));
        },
      );

      test('When stop called twice, Then second stop is a no-op', () async {
        recorder.writeFrame(frame1, 0.0);
        recorder.writeFrame(Uint8List.fromList([4, 5, 6]), 0.04);
        recorder.stop();

        final countAfterFirstStop = mockSink.writtenFrames.length;
        recorder.stop();

        expect(mockSink.writtenFrames.length, equals(countAfterFirstStop));
      });

      test(
        'When new, Then isStopped is false; after stop, isStopped is true',
        () async {
          expect(recorder.isStopped, isFalse);

          recorder.stop();

          expect(recorder.isStopped, isTrue);
        },
      );

      test('When new, Then hasFailed is false', () {
        expect(recorder.hasFailed, isFalse);
      });

      test(
        'When stop after 3-second wall-clock gap, Then padding is ~3 seconds (not fixed 1s)',
        () async {
          final frame2 = Uint8List.fromList([4, 5, 6]);

          recorder.writeFrame(frame1, 0.0);
          recorder.writeFrame(frame2, 0.04); // 1 frame later

          // Simulate 3 seconds of wall-clock time passing
          await Future<void>.delayed(const Duration(seconds: 3));
          recorder.stop();

          // 1 frame of frame1 (gap 0→1) + padding of frame2
          // With wall-clock padding of ~3s: ~75 frames of padding
          // With fixed 1s padding: only 25 frames
          // Total should be > 50 (proving it's not the fixed 1s)
          expect(mockSink.writtenFrames.length, greaterThan(50));
        },
      );

      test('When backwards timestamp, Then treated as zero repeats', () async {
        final frame2 = Uint8List.fromList([4, 5, 6]);

        recorder.writeFrame(frame1, 1.0);
        recorder.writeFrame(frame2, 0.5);

        expect(mockSink.writtenFrames, isEmpty);
      });
    });

    group('Given createWhiteRgba', () {
      test(
        'When called with 4x2, Then returns width*height*4 bytes all set to 255',
        () {
          final rgba = VideoRecorder.createWhiteRgba(4, 2);

          expect(rgba.length, equals(4 * 2 * 4));
          for (final byte in rgba) {
            expect(byte, equals(255));
          }
        },
      );
    });

    group('Given a recorder with a failing sink', () {
      test(
        'When sink throws StateError, Then hasFailed becomes true and error is rethrown',
        () {
          final failingSink = FailingFfmpegSink(failAfter: 0);
          final rec = VideoRecorder(VideoRecorderOptions(fps: 25), failingSink);

          rec.writeFrame(frame1, 0.0); // stored, no sink write
          expect(
            () => rec.writeFrame(Uint8List.fromList([4, 5, 6]), 0.2),
            throwsA(isA<StateError>()),
          );
          expect(rec.hasFailed, isTrue);
        },
      );

      test(
        'When hasFailed is true, Then subsequent writeFrame calls are silently discarded',
        () {
          final failingSink = FailingFfmpegSink(failAfter: 0);
          final rec = VideoRecorder(VideoRecorderOptions(fps: 25), failingSink);

          rec.writeFrame(frame1, 0.0);
          // Trigger the failure
          try {
            rec.writeFrame(Uint8List.fromList([4, 5, 6]), 0.2);
          } on StateError {
            // expected
          }

          // This should not throw or write anything
          rec.writeFrame(Uint8List.fromList([7, 8, 9]), 0.4);
          expect(failingSink.writtenFrames, isEmpty);
        },
      );
    });

    group('Given a recorder with a sink that throws a non-StateError', () {
      test('When sink throws IOException, Then hasFailed becomes true', () {
        final sink = IoExceptionSink();
        final rec = VideoRecorder(VideoRecorderOptions(fps: 25), sink);

        rec.writeFrame(frame1, 0.0); // stored, no sink write
        expect(
          () => rec.writeFrame(Uint8List.fromList([4, 5, 6]), 0.2),
          throwsException,
        );
        expect(rec.hasFailed, isTrue);
      });
    });

    group('Given frames of varying byte sizes', () {
      setUp(() {
        recorder = VideoRecorder(VideoRecorderOptions(fps: 25), mockSink);
      });

      test(
        'When frames arrive with different payload sizes, '
        'Then the recorder accepts them without error '
        '(dimension normalization is handled by the Flutter-side capture)',
        () async {
          final smallFrame = Uint8List.fromList([0x01, 0x02, 0x03]);
          final largeFrame = Uint8List(1000);

          recorder.writeFrame(smallFrame, 0.0);
          recorder.writeFrame(largeFrame, 0.04);

          // At 25fps, timestamps 0.0s and 0.04s both map to frame 0,
          // so the first frame is repeated 1 time (gap of 1 frame).
          expect(mockSink.writtenFrames.length, 1);
          expect(mockSink.writtenFrames.first, equals(smallFrame));
        },
      );
    });

    group('Given a recorder with fps=30', () {
      setUp(() {
        recorder = VideoRecorder(VideoRecorderOptions(fps: 30), mockSink);
      });

      test('When one-second gap, Then 30 frames are repeated', () async {
        final frame2 = Uint8List.fromList([4, 5, 6]);

        recorder.writeFrame(frame1, 0.0);
        recorder.writeFrame(frame2, 1.0);

        expect(mockSink.writtenFrames, hasLength(30));
      });
    });
  });
}
