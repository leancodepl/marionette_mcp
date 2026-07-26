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
      'scrolls the list inside the within_key scope, not the first one',
      timeout: _timeout,
      (WidgetTester tester) async {
        final firstController = ScrollController();
        final secondController = ScrollController();
        addTearDown(firstController.dispose);
        addTearDown(secondController.dispose);

        Widget cell(String cellKey, ScrollController controller) {
          return Expanded(
            child: Column(
              key: ValueKey(cellKey),
              children: [
                Expanded(
                  child: _buildItems(
                    controller: controller,
                    itemCount: 20,
                    itemExtent: 80,
                  ),
                ),
              ],
            ),
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  cell('grid.cell_1', firstController),
                  cell('grid.cell_2', secondController),
                ],
              ),
            ),
          ),
        );

        final simulator = ScrollSimulator(
          _PositionalGestureDispatcher(tester),
          WidgetFinder(),
        );

        await simulator.scrollUntilVisible(
          const KeyMatcher('item_15'),
          _configuration,
          scope: const KeyMatcher('grid.cell_2'),
        );
        await tester.pump();

        expect(secondController.offset, greaterThan(0));
        expect(
          firstController.offset,
          0,
          reason: 'the list outside the scope must not be scrolled',
        );
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
      body: _buildItems(
        controller: controller,
        itemCount: itemCount,
        itemExtent: itemExtent,
      ),
    ),
  );
}

Widget _buildItems({
  required ScrollController controller,
  required int itemCount,
  required double itemExtent,
}) {
  return ListView.builder(
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
  );
}

/// Drags wherever the simulator asks, so the scrollable it picked is the one
/// that actually moves.
class _PositionalGestureDispatcher extends GestureDispatcher {
  _PositionalGestureDispatcher(this._tester);

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
