import 'package:marionette_mcp/src/video/video_options.dart';
import 'package:test/test.dart';

void main() {
  group('validateVideoSize', () {
    group('Given no arguments', () {
      test('When called, Then returns 800x600', () {
        final result = validateVideoSize();

        expect(result.width, equals(800));
        expect(result.height, equals(600));
      });
    });

    group('Given a large viewport', () {
      test(
        'When 1920x1080, Then scales down to fit 800x800 with even dims',
        () {
          final result = validateVideoSize(
            viewportSize: (width: 1920, height: 1080),
          );

          expect(result.width, lessThanOrEqualTo(800));
          expect(result.height, lessThanOrEqualTo(800));
          expect(result.width.isEven, isTrue);
          expect(result.height.isEven, isTrue);
        },
      );
    });

    group('Given a portrait viewport', () {
      test(
        'When 1170x2532, Then scales down to fit 800x800 with even dims',
        () {
          final result = validateVideoSize(
            viewportSize: (width: 1170, height: 2532),
          );

          expect(result.width, lessThanOrEqualTo(800));
          expect(result.height, lessThanOrEqualTo(800));
          expect(result.width.isEven, isTrue);
          expect(result.height.isEven, isTrue);
        },
      );
    });

    group('Given a small viewport', () {
      test('When 320x240, Then returns exactly 320x240 (no upscale)', () {
        final result = validateVideoSize(
          viewportSize: (width: 320, height: 240),
        );

        expect(result.width, equals(320));
        expect(result.height, equals(240));
      });
    });

    group('Given explicit even dimensions', () {
      test('When size is 640x480, Then returns 640x480', () {
        final result = validateVideoSize(size: (width: 640, height: 480));

        expect(result.width, equals(640));
        expect(result.height, equals(480));
      });
    });

    group('Given explicit odd dimensions', () {
      test('When size is 641x481, Then rounds down to 640x480', () {
        final result = validateVideoSize(size: (width: 641, height: 481));

        expect(result.width, equals(640));
        expect(result.height, equals(480));
      });
    });

    group('Given both size and viewport', () {
      test('When both provided, Then explicit size takes precedence', () {
        final result = validateVideoSize(
          size: (width: 640, height: 480),
          viewportSize: (width: 1920, height: 1080),
        );

        expect(result.width, equals(640));
        expect(result.height, equals(480));
      });
    });

    group('Given zero viewport', () {
      test('When 0x0, Then returns positive even dimensions', () {
        final result = validateVideoSize(viewportSize: (width: 0, height: 0));

        expect(result.width, greaterThan(0));
        expect(result.height, greaterThan(0));
        expect(result.width.isEven, isTrue);
        expect(result.height.isEven, isTrue);
      });
    });

    group('Given a square viewport', () {
      test('When 800x800, Then returns 800x800 unchanged', () {
        final result = validateVideoSize(
          viewportSize: (width: 800, height: 800),
        );

        expect(result.width, equals(800));
        expect(result.height, equals(800));
      });
    });

    group('Given a 4K viewport', () {
      test('When 3840x2160, Then scales down to fit within 800x800', () {
        final result = validateVideoSize(
          viewportSize: (width: 3840, height: 2160),
        );

        expect(result.width, lessThanOrEqualTo(800));
        expect(result.height, lessThanOrEqualTo(800));
        expect(result.width.isEven, isTrue);
        expect(result.height.isEven, isTrue);
      });
    });

    group('Given tiny explicit dimensions', () {
      test('When size is 1x1, Then clamps to minimum 2x2', () {
        final result = validateVideoSize(size: (width: 1, height: 1));

        expect(result.width, equals(2));
        expect(result.height, equals(2));
      });

      test('When size is 3x3, Then rounds to 2x2 (3 & ~1 = 2)', () {
        final result = validateVideoSize(size: (width: 3, height: 3));

        expect(result.width, equals(2));
        expect(result.height, equals(2));
      });
    });

    group('Given explicit odd dimensions (partial)', () {
      test('When only width is odd, Then only width is rounded down', () {
        final result = validateVideoSize(size: (width: 641, height: 480));

        expect(result.width, equals(640));
        expect(result.height, equals(480));
      });

      test('When only height is odd, Then only height is rounded down', () {
        final result = validateVideoSize(size: (width: 640, height: 481));

        expect(result.width, equals(640));
        expect(result.height, equals(480));
      });
    });
  });

  group('VideoOptions', () {
    group('Given valid parameters', () {
      test('When constructed, Then stores all fields with fps default 25', () {
        final options = VideoOptions(
          width: 800,
          height: 600,
          outputFile: '/tmp/test.webm',
        );

        expect(options.width, equals(800));
        expect(options.height, equals(600));
        expect(options.outputFile, equals('/tmp/test.webm'));
        expect(options.fps, equals(25));
      });
    });

    group('Given custom fps', () {
      test('When constructed with fps=30, Then stores custom fps', () {
        final options = VideoOptions(
          width: 800,
          height: 600,
          outputFile: '/tmp/test.webm',
          fps: 30,
        );

        expect(options.fps, equals(30));
      });
    });

    group('Given invalid output file extension', () {
      test('When .mp4, Then throws ArgumentError', () {
        expect(
          () => VideoOptions(
            width: 800,
            height: 600,
            outputFile: '/tmp/test.mp4',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Given zero or negative dimensions', () {
      test('When width is 0, Then throws ArgumentError', () {
        expect(
          () =>
              VideoOptions(width: 0, height: 600, outputFile: '/tmp/test.webm'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('When height is negative, Then throws ArgumentError', () {
        expect(
          () => VideoOptions(
            width: 800,
            height: -1,
            outputFile: '/tmp/test.webm',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Given zero or negative fps', () {
      test('When fps is 0, Then throws ArgumentError', () {
        expect(
          () => VideoOptions(
            width: 800,
            height: 600,
            outputFile: '/tmp/test.webm',
            fps: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('When fps is negative, Then throws ArgumentError', () {
        expect(
          () => VideoOptions(
            width: 800,
            height: 600,
            outputFile: '/tmp/test.webm',
            fps: -1,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Given odd dimensions', () {
      test('When width is odd, Then throws ArgumentError', () {
        expect(
          () => VideoOptions(
            width: 801,
            height: 600,
            outputFile: '/tmp/test.webm',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('When height is odd, Then throws ArgumentError', () {
        expect(
          () => VideoOptions(
            width: 800,
            height: 601,
            outputFile: '/tmp/test.webm',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
