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
          _WidgetTesterGestureDispatcher(tester),
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
          _WidgetTesterGestureDispatcher(tester),
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

        final dispatcher = _WidgetTesterGestureDispatcher(tester);
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
      'chooses the hittable modal scroll layer when duplicate key exists behind a barrier',
      timeout: _timeout,
      (WidgetTester tester) async {
        final backgroundController = ScrollController();
        final modalController = ScrollController();

        addTearDown(() {
          backgroundController.dispose();
          modalController.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          controller: backgroundController,
                          itemCount: 100,
                          itemBuilder: (context, index) {
                            return ListTile(
                              key: ValueKey('shared_target_$index'),
                              title: Text('Background $index'),
                            );
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            builder: (_) {
                              return SizedBox(
                                height: 320,
                                child: ListView.builder(
                                  controller: modalController,
                                  itemCount: 100,
                                  itemBuilder: (context, index) {
                                    return ListTile(
                                      key: ValueKey('shared_target_$index'),
                                      title: Text('Modal $index'),
                                    );
                                  },
                                ),
                              );
                            },
                          );
                        },
                        child: const Text('open modal'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('open modal'));
        await tester.pumpAndSettle();

        final simulator = ScrollSimulator(
          _WidgetTesterGestureDispatcher(tester),
          WidgetFinder(),
        );
        await simulator.scrollUntilVisible(
          const KeyMatcher('shared_target_90'),
          _configuration,
        );
        await tester.pumpAndSettle();

        expect(modalController.offset, greaterThan(0));
        expect(backgroundController.offset, 0);
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

class _WidgetTesterGestureDispatcher extends GestureDispatcher {
  _WidgetTesterGestureDispatcher(this._tester);

  final WidgetTester _tester;
  int dragCount = 0;

  @override
  Future<void> drag(Offset from, Offset to) async {
    dragCount++;
    await _tester.dragFrom(from, to - from);
    await _tester.pump();
  }
}
