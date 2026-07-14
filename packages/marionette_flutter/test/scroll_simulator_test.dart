import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/scroll_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _timeout = Timeout(Duration(seconds: 30));
const _configuration = MarionetteConfiguration();

void main() {
  group('ScrollSimulator.scrollUntilVisible', () {
    testWidgets(
      'scrolls down then finds a target above by reversing direction',
      timeout: _timeout,
      (WidgetTester tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _buildItemsApp(
            controller: controller,
            itemCount: 20,
            itemExtent: 80,
          ),
        );

        final simulator = ScrollSimulator(
          _WidgetTesterGestureDispatcher(tester, find.byType(Scrollable).first),
          WidgetFinder(),
        );

        await simulator.scrollUntilVisible(
          const KeyMatcher('item_10'),
          _configuration,
        );
        await tester.pump();

        final offsetAfterScrollingDown = controller.offset;
        expect(find.byKey(const ValueKey('item_10')), findsOneWidget);
        expect(offsetAfterScrollingDown, greaterThan(0));

        await simulator.scrollUntilVisible(
          const KeyMatcher('item_2'),
          _configuration,
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('item_2')), findsOneWidget);
        expect(controller.offset, lessThan(offsetAfterScrollingDown));
      },
    );

    testWidgets(
      'uses adaptive attempts and reaches targets beyond 50 when needed',
      timeout: _timeout,
      (WidgetTester tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _buildItemsApp(
            controller: controller,
            itemCount: 140,
            itemExtent: 80,
          ),
        );

        final simulator = ScrollSimulator(
          _WidgetTesterGestureDispatcher(tester, find.byType(Scrollable).first),
          WidgetFinder(),
        );

        await simulator.scrollUntilVisible(
          const KeyMatcher('item_90'),
          _configuration,
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('item_90')), findsOneWidget);
        expect(controller.offset, greaterThan(50 * 64.0));
      },
    );

    testWidgets(
      'applies a hard default cap for very large scroll extents',
      timeout: _timeout,
      (WidgetTester tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _buildItemsApp(
            controller: controller,
            itemCount: 10000,
            itemExtent: 80,
          ),
        );

        final dispatcher = _WidgetTesterGestureDispatcher(
          tester,
          find.byType(Scrollable).first,
        );
        final simulator = ScrollSimulator(dispatcher, WidgetFinder());

        await expectLater(
          () => simulator.scrollUntilVisible(
            const KeyMatcher('missing_item'),
            _configuration,
          ),
          throwsA(isA<StateError>()),
        );
        await tester.pump();

        expect(dispatcher.dragCount, 200);
      },
    );

    testWidgets(
      'picks the main list over a smaller auxiliary scrollable that '
      'appears first in the tree',
      timeout: _timeout,
      (WidgetTester tester) async {
        // Regression test for #76: a screen with a small horizontal chip
        // row above the main vertical list used to make the fallback
        // scrollable search latch onto the chip row (first
        // scrollable-with-range found in traversal order) instead of the
        // list actually containing the target, so scrollUntilVisible
        // dragged the wrong axis and never reached below-the-fold targets.
        final listController = ScrollController();
        addTearDown(listController.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 30,
                      itemBuilder: (context, index) => SizedBox(
                        width: 60,
                        child: Center(child: Text('Chip $index')),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: listController,
                      physics: const ClampingScrollPhysics(),
                      itemCount: 60,
                      itemBuilder: (context, index) => ListTile(
                        key: ValueKey('item_$index'),
                        minTileHeight: 80,
                        title: Text('Item $index'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final simulator = ScrollSimulator(
          _LocationBasedGestureDispatcher(tester),
          WidgetFinder(),
        );

        await simulator.scrollUntilVisible(
          const KeyMatcher('item_40'),
          _configuration,
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('item_40')), findsOneWidget);
        expect(listController.offset, greaterThan(0));
      },
    );
  });
}

Widget _buildItemsApp({
  required ScrollController controller,
  required int itemCount,
  required double itemExtent,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView.builder(
        controller: controller,
        physics: const ClampingScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (BuildContext context, int index) {
          return ListTile(
            key: ValueKey('item_$index'),
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text('Item $index'),
            subtitle: const Text('Scroll target for marionette.scrollTo'),
            minTileHeight: itemExtent,
          );
        },
      ),
    ),
  );
}

/// Mirrors the real [GestureDispatcher.drag]: dispatches the gesture at the
/// given screen coordinates and lets Flutter's hit-testing route it,
/// instead of targeting a fixed [Finder]. Needed to catch bugs where the
/// wrong Scrollable is selected, since a Finder-based double would always
/// drag the pre-selected widget regardless of what the simulator picked.
class _LocationBasedGestureDispatcher extends GestureDispatcher {
  _LocationBasedGestureDispatcher(this._tester);

  final WidgetTester _tester;

  @override
  Future<void> drag(Offset from, Offset to) async {
    await _tester.dragFrom(from, to - from);
    await _tester.pump();
  }
}

class _WidgetTesterGestureDispatcher extends GestureDispatcher {
  _WidgetTesterGestureDispatcher(this._tester, this._scrollableFinder);

  final WidgetTester _tester;
  final Finder _scrollableFinder;
  int dragCount = 0;

  @override
  Future<void> drag(Offset from, Offset to) async {
    dragCount++;
    await _tester.drag(_scrollableFinder, to - from);
    await _tester.pump();
  }
}
