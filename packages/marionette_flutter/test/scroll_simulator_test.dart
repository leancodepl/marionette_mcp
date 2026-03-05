import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/scroll_simulator.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _timeout = Timeout(Duration(seconds: 30));
const _configuration = MarionetteConfiguration();
const _listItemCount = 100;

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
  });

  group('ScrollSimulator.scrollUntilVisible on layered UIs', () {
    testWidgets(
      'scrolls the modal list instead of the covered one behind it',
      timeout: _timeout,
      (WidgetTester tester) async {
        final backgroundController = ScrollController();
        final sheetController = ScrollController();
        addTearDown(() {
          backgroundController.dispose();
          sheetController.dispose();
        });

        // Every widget here is uniquely named. The only thing that makes the
        // covered list win is that it is built first, so it comes first in
        // the element tree.
        await tester.pumpWidget(
          _buildSheetApp(
            background: Expanded(
              child: _lazyList(
                controller: backgroundController,
                label: (int index) => 'Background item $index',
              ),
            ),
            sheet: _lazyList(
              controller: sheetController,
              label: (int index) => 'Country $index',
            ),
          ),
        );

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();

        final simulator = ScrollSimulator(
          _CoordinateGestureDispatcher(tester),
          WidgetFinder(),
        );

        // 'Country 90' is far down the sheet's list, so it is not built yet
        // and cannot be located by matching alone.
        await simulator.scrollUntilVisible(
          const TextMatcher('Country 90'),
          _configuration,
        );
        await tester.pumpAndSettle();

        expect(find.text('Country 90'), findsOneWidget);
        expect(
          backgroundController.offset,
          0,
          reason: 'the covered list should never be scrolled',
        );
        expect(sheetController.offset, greaterThan(0));
      },
    );

    testWidgets(
      'scrolls the list holding the copy of the target the user can reach',
      timeout: _timeout,
      (WidgetTester tester) async {
        final backgroundController = ScrollController();
        final sheetController = ScrollController();
        addTearDown(() {
          backgroundController.dispose();
          sheetController.dispose();
        });

        // Both layers build every row up front, so the covered list holds a
        // matching row that is in the element tree and comes first. Picking
        // the scrollable that owns the first match drags the covered list.
        await tester.pumpWidget(
          _buildSheetApp(
            background: Expanded(
              child: _eagerList(
                controller: backgroundController,
                label: (int index) => index == 4 ? 'Save' : 'Note $index',
              ),
            ),
            sheet: _eagerList(
              controller: sheetController,
              label: (int index) => index == 90 ? 'Save' : 'Option $index',
            ),
          ),
        );

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();

        final simulator = ScrollSimulator(
          _CoordinateGestureDispatcher(tester),
          WidgetFinder(),
        );

        await simulator.scrollUntilVisible(
          const TextMatcher('Save'),
          _configuration,
        );
        await tester.pumpAndSettle();

        expect(find.text('Save'), findsNWidgets(2));
        expect(
          find.text('Save').hitTestable(),
          findsOneWidget,
          reason: 'the sheet copy should be the one brought into reach',
        );
        expect(
          backgroundController.offset,
          0,
          reason: 'the covered list should never be scrolled',
        );
        expect(sheetController.offset, greaterThan(0));
      },
    );

    testWidgets(
      'stops once the target is visible even if a covered widget matches too',
      timeout: _timeout,
      (WidgetTester tester) async {
        final sheetController = ScrollController();
        addTearDown(sheetController.dispose);

        // The page behind the sheet holds a matching 'Save' label, but it is
        // not inside any scrollable, so the right scrollable is still picked.
        // Only the "am I done yet?" check can fail here.
        await tester.pumpWidget(
          _buildSheetApp(
            background: const Text('Save'),
            sheet: _lazyList(
              controller: sheetController,
              label: (int index) => index == 90 ? 'Save' : 'Option $index',
            ),
          ),
        );

        await tester.tap(find.text('open sheet'));
        await tester.pumpAndSettle();

        final simulator = ScrollSimulator(
          _CoordinateGestureDispatcher(tester),
          WidgetFinder(),
        );

        await simulator.scrollUntilVisible(
          const TextMatcher('Save'),
          _configuration,
        );
        await tester.pumpAndSettle();

        expect(find.text('Save'), findsNWidgets(2));
        expect(
          find.text('Save').hitTestable(),
          findsOneWidget,
          reason: 'the covered copy must not be what ended the scroll',
        );
        expect(sheetController.offset, greaterThan(0));
      },
    );

    testWidgets(
      'does not drag a scrollable it knows the user cannot reach',
      timeout: _timeout,
      (WidgetTester tester) async {
        final listController = ScrollController();
        final chipController = ScrollController();
        addTearDown(() {
          listController.dispose();
          chipController.dispose();
        });

        await tester.pumpWidget(
          _buildCoveredListApp(
            listController: listController,
            chipController: chipController,
          ),
        );

        final dispatcher = _CoordinateGestureDispatcher(tester);
        final simulator = ScrollSimulator(dispatcher, WidgetFinder());

        // Neither scrollable can reveal the target: the covered list cannot be
        // dragged at all, because a drag starts at the same centre point the
        // reachability check uses, and the chip row has nowhere to scroll.
        await expectLater(
          () => simulator.scrollUntilVisible(
            const TextMatcher('Item 90'),
            _configuration,
          ),
          throwsA(isA<StateError>()),
        );
        await tester.pumpAndSettle();

        expect(
          dispatcher.dragCount,
          0,
          reason: 'no gesture should be aimed at a point known to be covered',
        );
        expect(listController.offset, 0);
        expect(chipController.offset, 0);
      },
    );
  });
}

/// A page holding [background] under a modal bottom sheet holding [sheet].
///
/// Once the sheet is open the background stays built and stays earlier in the
/// element tree, which is what makes it a layered UI.
Widget _buildSheetApp({required Widget sheet, Widget? background}) {
  return MaterialApp(
    home: Builder(
      builder: (BuildContext context) {
        return Scaffold(
          body: Column(
            children: <Widget>[
              if (background != null) background,
              TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (BuildContext context) =>
                        SizedBox(height: 320, child: sheet),
                  );
                },
                child: const Text('open sheet'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// A list that builds rows on demand, so a row far down does not exist in the
/// element tree until it is scrolled near.
Widget _lazyList({
  required ScrollController controller,
  required String Function(int index) label,
}) {
  return ListView.builder(
    controller: controller,
    physics: const ClampingScrollPhysics(),
    itemCount: _listItemCount,
    itemBuilder: (BuildContext context, int index) =>
        ListTile(title: Text(label(index))),
  );
}

/// A list that builds every row up front, so a row scrolled out of view is
/// still in the element tree and can be matched.
Widget _eagerList({
  required ScrollController controller,
  required String Function(int index) label,
}) {
  return SingleChildScrollView(
    controller: controller,
    physics: const ClampingScrollPhysics(),
    child: Column(
      children: <Widget>[
        for (int index = 0; index < _listItemCount; index++)
          ListTile(title: Text(label(index))),
      ],
    ),
  );
}

/// A scrolling list whose centre is swallowed by a layer above it, next to a
/// reachable row of chips that has nothing to scroll.
Widget _buildCoveredListApp({
  required ScrollController listController,
  required ScrollController chipController,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          ListView.builder(
            controller: listController,
            physics: const ClampingScrollPhysics(),
            itemCount: _listItemCount,
            itemBuilder: (BuildContext context, int index) =>
                ListTile(title: Text('Item $index'), minTileHeight: 80),
          ),
          const Center(
            child: AbsorbPointer(child: SizedBox(width: 300, height: 300)),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 48,
              child: SingleChildScrollView(
                controller: chipController,
                scrollDirection: Axis.horizontal,
                child: const Row(children: <Widget>[Text('chip')]),
              ),
            ),
          ),
        ],
      ),
    ),
  );
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

/// Drags from the exact coordinates the simulator asked for, the way the real
/// [GestureDispatcher] does. Which scrollable moves is then decided by the
/// simulator, not by the test.
class _CoordinateGestureDispatcher extends GestureDispatcher {
  _CoordinateGestureDispatcher(this._tester);

  final WidgetTester _tester;
  int dragCount = 0;

  @override
  Future<void> drag(Offset from, Offset to) async {
    dragCount++;
    await _tester.dragFrom(from, to - from);
    await _tester.pump();
  }
}
