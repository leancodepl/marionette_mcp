import 'package:marionette_mcp/src/native_service/tools/gesture_tools.dart';
import 'package:test/test.dart';

void main() {
  group('cappedSwipeHalf', () {
    test('limits vertical swipes to viewport height', () {
      expect(
        cappedSwipeHalf(
          direction: SwipeDirection.up,
          half: 200,
          centerX: 100,
          centerY: 50,
          maxX: 200,
          maxY: 100,
        ),
        50,
      );
    });

    test('limits horizontal swipes to viewport width', () {
      expect(
        cappedSwipeHalf(
          direction: SwipeDirection.left,
          half: 200,
          centerX: 30,
          centerY: 100,
          maxX: 60,
          maxY: 200,
        ),
        30,
      );
    });

    test('keeps requested half when viewport is large enough', () {
      expect(
        cappedSwipeHalf(
          direction: SwipeDirection.down,
          half: 100,
          centerX: 540,
          centerY: 960,
          maxX: 1080,
          maxY: 1920,
        ),
        100,
      );
    });
  });

  group('SwipeDirection.swipeEndpoints with capped half', () {
    test('vertical swipe stays within viewport bounds', () {
      const maxY = 100;
      const centerY = 50;
      final half = cappedSwipeHalf(
        direction: SwipeDirection.up,
        half: 200,
        centerX: 50,
        centerY: centerY,
        maxX: 100,
        maxY: maxY,
      );

      final endpoints = SwipeDirection.up.swipeEndpoints(
        centerX: 50,
        centerY: centerY,
        half: half,
      );

      expect(endpoints.startY, greaterThanOrEqualTo(0));
      expect(endpoints.endY, greaterThanOrEqualTo(0));
      expect(endpoints.startY, lessThanOrEqualTo(maxY));
      expect(endpoints.endY, lessThanOrEqualTo(maxY));
    });
  });
}
