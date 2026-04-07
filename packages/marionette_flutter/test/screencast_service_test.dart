import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/screencast_service.dart';

/// Creates raw RGBA bytes for the given dimensions.
Uint8List _createRgba(int width, int height,
    {int r = 255, int g = 0, int b = 0}) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = r;
    bytes[i + 1] = g;
    bytes[i + 2] = b;
    bytes[i + 3] = 255;
  }
  return bytes;
}

/// A fake frame capturer that returns synthetic RGBA bytes without touching the GPU.
Future<CapturedFrame?> fakeFrameCapturer(
  RenderView renderView, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final size = renderView.flutterView.physicalSize;
  if (size.isEmpty) return null;

  final width = targetWidth ?? size.width.round();
  final height = targetHeight ?? size.height.round();

  return CapturedFrame(
    bytes: _createRgba(width, height),
    width: width,
    height: height,
  );
}

void main() {
  group('ScreencastFrame', () {
    test('stores rgbaBytes, timestampMs, width, and height', () {
      final bytes = Uint8List.fromList([0xFF, 0x00, 0x00, 0xFF]);
      final frame = ScreencastFrame(
        rgbaBytes: bytes,
        timestampMs: 1234567890,
        width: 800,
        height: 600,
      );

      expect(frame.rgbaBytes, equals(bytes));
      expect(frame.timestampMs, equals(1234567890));
      expect(frame.width, equals(800));
      expect(frame.height, equals(600));
    });
  });

  group('ScreencastService', () {
    group('Given a new service', () {
      test('When start is called, Then isActive is true', () {
        final service = ScreencastService();

        service.start(onFrame: (_) async {});

        expect(service.isActive, isTrue);
      });

      test('When start is called twice, Then second call throws StateError',
          () {
        final service = ScreencastService();
        service.start(onFrame: (_) async {});

        expect(() => service.start(onFrame: (_) async {}), throwsStateError);
      });

      test('When start then stop is called, Then isActive is false', () async {
        final service = ScreencastService();
        service.start(onFrame: (_) async {});

        await service.stop();

        expect(service.isActive, isFalse);
      });
    });

    testWidgets('When started with a widget, Then captures frames',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      // Pump several frames at 40ms intervals
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();

      expect(frames.length, greaterThanOrEqualTo(3));
    });

    testWidgets(
        'When capturing frames, Then rgbaBytes are raw RGBA (width*height*4 bytes)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();

      expect(frames, isNotEmpty);
      for (final frame in frames) {
        expect(frame.rgbaBytes.length, equals(frame.width * frame.height * 4));
      }
    });

    testWidgets('When capturing, Then each frame has non-empty image data',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();

      expect(frames, isNotEmpty);
      for (final frame in frames) {
        expect(frame.rgbaBytes, isNotEmpty);
      }
    });

    testWidgets('When capturing, Then each frame has a timestamp > 0',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();

      expect(frames, isNotEmpty);
      for (final frame in frames) {
        expect(frame.timestampMs, greaterThan(0));
      }
    });

    testWidgets(
        'When capturing multiple frames, Then timestamps are monotonically increasing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();

      expect(frames.length, greaterThanOrEqualTo(2));
      for (var i = 1; i < frames.length; i++) {
        expect(
          frames[i].timestampMs,
          greaterThanOrEqualTo(frames[i - 1].timestampMs),
        );
      }
    });

    testWidgets(
        'When capturing, Then each frame reports positive viewport dimensions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();

      expect(frames, isNotEmpty);
      for (final frame in frames) {
        expect(frame.width, greaterThan(0));
        expect(frame.height, greaterThan(0));
      }
    });

    testWidgets(
        'When consumer is slow, Then frames are skipped (back-pressure)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
        // Simulate a slow consumer — takes 200ms to process each frame
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      // Pump 12 ticks at 40ms = 480ms total
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();

      // With 200ms processing time and 40ms intervals,
      // at most ~2-3 frames should be delivered, never 6+
      expect(frames.length, lessThan(6));
    });

    testWidgets(
        'When stop is called during in-flight capture, Then waits for completion',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      var callbackCompleted = false;
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        callbackCompleted = true;
      });

      // Pump one tick to trigger a capture
      await tester.pump(const Duration(milliseconds: 40));

      // Start stop (don't await yet — the in-flight callback needs time to advance)
      final stopFuture = service.stop();

      // Advance the clock so the delayed future inside onFrame resolves
      await tester.pump(const Duration(milliseconds: 100));

      await stopFuture;

      expect(callbackCompleted, isTrue);
    });

    testWidgets('When maxSize is set, Then frame dimensions are constrained',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];

      final service = ScreencastService(
        maxSize: const Size(400, 300),
        frameCapturer: (renderView,
            {int? targetWidth, int? targetHeight}) async {
          final w = targetWidth ?? 800;
          final h = targetHeight ?? 600;
          return CapturedFrame(
            bytes: _createRgba(w, h),
            width: w,
            height: h,
          );
        },
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      expect(frames.first.width, lessThanOrEqualTo(400));
      expect(frames.first.height, lessThanOrEqualTo(300));
    });

    testWidgets(
        'When maxSize is set, Then RGBA byte count matches scaled dimensions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        maxSize: const Size(400, 300),
        frameCapturer: (renderView,
            {int? targetWidth, int? targetHeight}) async {
          final w = targetWidth ?? 800;
          final h = targetHeight ?? 600;
          return CapturedFrame(
            bytes: _createRgba(w, h),
            width: w,
            height: h,
          );
        },
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      final frame = frames.first;
      expect(frame.rgbaBytes.length, equals(frame.width * frame.height * 4));
      expect(frame.width, lessThanOrEqualTo(400));
      expect(frame.height, lessThanOrEqualTo(300));
    });

    testWidgets(
        'When capturing, Then first frame timestamp is elapsed (close to 0), not epoch time',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      expect(frames.first.timestampMs, lessThan(5000));
    });

    testWidgets('When restarted after stop, Then timestamps reset to near 0',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final service = ScreencastService(frameCapturer: fakeFrameCapturer);

      // First session
      service.start(onFrame: (frame) async {});
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await service.stop();

      // Second session — timestamps should reset to near 0
      final secondFrames = <ScreencastFrame>[];
      service.start(onFrame: (frame) async {
        secondFrames.add(frame);
      });
      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(secondFrames, isNotEmpty);
      expect(secondFrames.first.timestampMs, lessThan(5000));
    });

    testWidgets(
        'When capturing, Then capturer receives target dimensions matching viewport',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.blue)),
      );

      int? receivedTargetWidth;
      int? receivedTargetHeight;
      final service = ScreencastService(
        frameCapturer: (renderView,
            {int? targetWidth, int? targetHeight}) async {
          receivedTargetWidth = targetWidth;
          receivedTargetHeight = targetHeight;
          final w = targetWidth ?? 100;
          final h = targetHeight ?? 100;
          return CapturedFrame(bytes: _createRgba(w, h), width: w, height: h);
        },
      );

      service.start(onFrame: (frame) async {});

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      final view = tester.view;
      expect(receivedTargetWidth, equals(view.physicalSize.width.round()));
      expect(receivedTargetHeight, equals(view.physicalSize.height.round()));
    });

    testWidgets(
        'When frame is captured, Then RGBA byte count matches width*height*4',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.green)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      final frame = frames.first;
      expect(frame.rgbaBytes.length, equals(frame.width * frame.height * 4));
    });

    testWidgets(
        'When maxSize is set with large viewport, Then scaled RGBA byte count matches dimensions',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        maxSize: const Size(400, 800),
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      final frame = frames.first;
      expect(frame.width, lessThanOrEqualTo(400));
      expect(frame.height, lessThanOrEqualTo(800));
      expect(frame.rgbaBytes.length, equals(frame.width * frame.height * 4));
    });

    testWidgets(
        'When maxSize downscaling produces odd dimensions, Then they are rounded to even',
        (tester) async {
      tester.view.physicalSize = const Size(900, 502);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        maxSize: const Size(400, 400),
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      expect(frames.first.width % 2, equals(0),
          reason: 'width ${frames.first.width} should be even');
      expect(frames.first.height % 2, equals(0),
          reason: 'height ${frames.first.height} should be even');
    });

    testWidgets(
        'When maxSize downscaling produces even dimensions, Then they are unchanged',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        maxSize: const Size(400, 300),
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      expect(frames.first.width, equals(400));
      expect(frames.first.height, equals(300));
    });

    testWidgets(
        'When frame is within maxSize bounds but has odd dimensions, Then dimensions are rounded to even',
        (tester) async {
      tester.view.physicalSize = const Size(799, 601);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        maxSize: const Size(800, 800),
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      expect(frames.first.width % 2, equals(0),
          reason: 'width ${frames.first.width} should be even');
      expect(frames.first.height % 2, equals(0),
          reason: 'height ${frames.first.height} should be even');
    });

    testWidgets(
        'When no maxSize is set, Then frames arrive at viewport dimensions',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      final view = tester.view;
      expect(frames, isNotEmpty);
      expect(frames.first.width, equals(view.physicalSize.width.round()));
      expect(frames.first.height, equals(view.physicalSize.height.round()));
    });

    testWidgets(
        'When extreme downscale would produce zero dimensions, Then clamps to minimum 2x2',
        (tester) async {
      tester.view.physicalSize = const Size(3, 3);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        maxSize: const Size(1, 1),
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      expect(frames.first.width, greaterThanOrEqualTo(2));
      expect(frames.first.height, greaterThanOrEqualTo(2));
    });

    testWidgets(
        'When 1x1 viewport is within maxSize bounds, Then clamps to minimum 2x2',
        (tester) async {
      tester.view.physicalSize = const Size(1, 1);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const MaterialApp(home: ColoredBox(color: Colors.red)),
      );

      final frames = <ScreencastFrame>[];
      final service = ScreencastService(
        maxSize: const Size(800, 800),
        frameCapturer: fakeFrameCapturer,
      );

      service.start(onFrame: (frame) async {
        frames.add(frame);
      });

      await tester.pump(const Duration(milliseconds: 40));
      await service.stop();

      expect(frames, isNotEmpty);
      expect(frames.first.width, greaterThanOrEqualTo(2));
      expect(frames.first.height, greaterThanOrEqualTo(2));
    });

    testWidgets('When no widget is pumped, Then does not crash',
        (tester) async {
      final service = ScreencastService(
        frameCapturer: (_, {int? targetWidth, int? targetHeight}) async => null,
      );

      service.start(onFrame: (frame) async {});

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      await service.stop();
    });
  });
}
