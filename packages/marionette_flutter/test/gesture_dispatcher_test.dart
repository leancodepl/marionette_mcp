import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _timeout = Timeout(Duration(seconds: 10));

void main() {
  group('GestureDispatcher.longPress', () {
    testWidgets(
      'should dispatch PointerDown, wait, then PointerUp with unique device id',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.longPress(
              const CoordinatesMatcher(100, 100),
              WidgetFinder(),
              const MarionetteConfiguration(),
              duration: const Duration(milliseconds: 50),
            ));
        await tester.pump();

        expect(events, isNotEmpty, reason: 'Should have dispatched events');

        // Verify correct event sequence: Added, Down, Up, Removed
        final addedEvents = events.whereType<PointerAddedEvent>().toList();
        final downEvents = events.whereType<PointerDownEvent>().toList();
        final upEvents = events.whereType<PointerUpEvent>().toList();
        final removedEvents = events.whereType<PointerRemovedEvent>().toList();

        expect(addedEvents, hasLength(1));
        expect(downEvents, hasLength(1));
        expect(upEvents, hasLength(1));
        expect(removedEvents, hasLength(1));

        for (final event in events) {
          expect(
            event.device,
            isNot(equals(0)),
            reason: '${event.runtimeType} should use a unique device id',
          );
        }
      },
    );

    testWidgets(
      'should send PointerRemovedEvent after long press to clean up pointer state',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.longPress(
              const CoordinatesMatcher(100, 100),
              WidgetFinder(),
              const MarionetteConfiguration(),
              duration: const Duration(milliseconds: 50),
            ));
        await tester.pump();

        final removedEvents = events.whereType<PointerRemovedEvent>().toList();

        expect(
          removedEvents,
          hasLength(1),
          reason: 'Long press should send exactly one PointerRemovedEvent to '
              'properly clean up pointer state',
        );
      },
    );
  });

  group('GestureDispatcher - Bug B5: macOS pointer device collision', () {
    testWidgets(
      'should use a unique device id (not 0) to avoid colliding with the real mouse',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        // runAsync escapes fake-async so Future.delayed resolves
        await tester.runAsync(() => dispatcher.tap(
              const CoordinatesMatcher(100, 100),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        expect(events, isNotEmpty, reason: 'Should have dispatched events');

        for (final event in events) {
          expect(
            event.device,
            isNot(equals(0)),
            reason: '${event.runtimeType} should use a unique device id, '
                'not 0 which is the real macOS mouse',
          );
        }
      },
    );

    testWidgets(
      'should send PointerRemovedEvent after each tap to clean up pointer state',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();

        // First tap
        await tester.runAsync(() => dispatcher.tap(
              const CoordinatesMatcher(100, 100),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        // Second tap
        await tester.runAsync(() => dispatcher.tap(
              const CoordinatesMatcher(200, 200),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        final removedEvents = events.whereType<PointerRemovedEvent>().toList();

        expect(
          removedEvents,
          hasLength(2),
          reason: 'Each tap should send a PointerRemovedEvent to properly '
              'clean up pointer state',
        );
      },
    );

    testWidgets(
      'drag should use a unique device id (not 0)',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.drag(const Offset(100, 100), const Offset(200, 200)),
        );
        await tester.pump();

        expect(events, isNotEmpty, reason: 'Should have dispatched events');

        for (final event in events) {
          expect(
            event.device,
            isNot(equals(0)),
            reason: '${event.runtimeType} should use a unique device id, '
                'not 0 which is the real macOS mouse',
          );
        }
      },
    );

    testWidgets(
      'drag should send PointerRemovedEvent to clean up pointer state',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.drag(const Offset(100, 100), const Offset(200, 200)),
        );
        await tester.pump();

        final removedEvents = events.whereType<PointerRemovedEvent>().toList();

        expect(
          removedEvents,
          hasLength(1),
          reason: 'A drag should send exactly one PointerRemovedEvent to '
              'properly clean up pointer state',
        );
      },
    );

    testWidgets(
      'MouseTracker asserts when duplicate PointerAddedEvent(mouse, device:0) is dispatched',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Center(child: Text('Hello'))),
          ),
        );

        // Simulate the real macOS mouse being present at device 0
        GestureBinding.instance.handlePointerEvent(
          const PointerAddedEvent(
            kind: PointerDeviceKind.mouse,
            device: 0,
            position: Offset(50, 50),
          ),
        );
        await tester.pump();

        // Dispatching a second PointerAddedEvent for the same mouse device
        // triggers a Flutter assertion — proving that any code using
        // device: 0 with mouse kind will crash when the real cursor exists.
        expect(
          () => GestureBinding.instance.handlePointerEvent(
            const PointerAddedEvent(
              kind: PointerDeviceKind.mouse,
              device: 0,
              position: Offset(100, 100),
            ),
          ),
          throwsA(isA<AssertionError>()),
          reason: 'Duplicate PointerAddedEvent(kind: mouse, device: 0) should '
              'trigger an assertion in MouseTracker — this is why '
              'GestureDispatcher must use a unique device id',
        );
      },
    );
  });

  group('GestureDispatcher - swipe', () {
    testWidgets(
      'swipe left computes correct end offset',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  key: const ValueKey('target'),
                  width: 200,
                  height: 200,
                  child: const Text('Swipe me'),
                ),
              ),
            ),
          ),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.swipe(
            const KeyMatcher('target'),
            WidgetFinder(),
            const MarionetteConfiguration(),
            direction: 'left',
            distance: 100.0,
          ),
        );
        await tester.pump();

        expect(events, isNotEmpty);
        final downEvent = events.whereType<PointerDownEvent>().first;
        final upEvent = events.whereType<PointerUpEvent>().first;

        // Swipe left means end.dx < start.dx, dy stays the same
        expect(upEvent.position.dx, lessThan(downEvent.position.dx));
        expect(
          (downEvent.position.dx - upEvent.position.dx).round(),
          equals(100),
        );
        expect(upEvent.position.dy, closeTo(downEvent.position.dy, 0.1));
      },
    );

    testWidgets(
      'swipe right computes correct end offset',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  key: const ValueKey('target'),
                  width: 200,
                  height: 200,
                  child: const Text('Swipe me'),
                ),
              ),
            ),
          ),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.swipe(
            const KeyMatcher('target'),
            WidgetFinder(),
            const MarionetteConfiguration(),
            direction: 'right',
            distance: 150.0,
          ),
        );
        await tester.pump();

        expect(events, isNotEmpty);
        final downEvent = events.whereType<PointerDownEvent>().first;
        final upEvent = events.whereType<PointerUpEvent>().first;

        expect(upEvent.position.dx, greaterThan(downEvent.position.dx));
        expect(
          (upEvent.position.dx - downEvent.position.dx).round(),
          equals(150),
        );
        expect(upEvent.position.dy, closeTo(downEvent.position.dy, 0.1));
      },
    );

    testWidgets(
      'swipe up computes correct end offset',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  key: const ValueKey('target'),
                  width: 200,
                  height: 200,
                  child: const Text('Swipe me'),
                ),
              ),
            ),
          ),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.swipe(
            const KeyMatcher('target'),
            WidgetFinder(),
            const MarionetteConfiguration(),
            direction: 'up',
            distance: 100.0,
          ),
        );
        await tester.pump();

        expect(events, isNotEmpty);
        final downEvent = events.whereType<PointerDownEvent>().first;
        final upEvent = events.whereType<PointerUpEvent>().first;

        expect(upEvent.position.dy, lessThan(downEvent.position.dy));
        expect(
          (downEvent.position.dy - upEvent.position.dy).round(),
          equals(100),
        );
        expect(upEvent.position.dx, closeTo(downEvent.position.dx, 0.1));
      },
    );

    testWidgets(
      'swipe down computes correct end offset',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  key: const ValueKey('target'),
                  width: 200,
                  height: 200,
                  child: const Text('Swipe me'),
                ),
              ),
            ),
          ),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.swipe(
            const KeyMatcher('target'),
            WidgetFinder(),
            const MarionetteConfiguration(),
            direction: 'down',
            distance: 100.0,
          ),
        );
        await tester.pump();

        expect(events, isNotEmpty);
        final downEvent = events.whereType<PointerDownEvent>().first;
        final upEvent = events.whereType<PointerUpEvent>().first;

        expect(upEvent.position.dy, greaterThan(downEvent.position.dy));
        expect(
          (upEvent.position.dy - downEvent.position.dy).round(),
          equals(100),
        );
        expect(upEvent.position.dx, closeTo(downEvent.position.dx, 0.1));
      },
    );

    testWidgets(
      'swipe with invalid direction throws ArgumentError',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  key: const ValueKey('target'),
                  width: 200,
                  height: 200,
                  child: const Text('Swipe me'),
                ),
              ),
            ),
          ),
        );

        final dispatcher = GestureDispatcher();
        Object? caughtError;
        await tester.runAsync(() async {
          try {
            await dispatcher.swipe(
              const KeyMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
              direction: 'diagonal',
            );
          } catch (e) {
            caughtError = e;
          }
        });
        expect(caughtError, isA<ArgumentError>());
      },
    );

    testWidgets(
      'swipe with non-existent element throws Exception',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Center(child: Text('Hello'))),
          ),
        );

        final dispatcher = GestureDispatcher();
        Object? caughtError;
        await tester.runAsync(() async {
          try {
            await dispatcher.swipe(
              const KeyMatcher('nonexistent'),
              WidgetFinder(),
              const MarionetteConfiguration(),
              direction: 'left',
            );
          } catch (e) {
            caughtError = e;
          }
        });
        expect(caughtError, isA<Exception>());
      },
    );
  });

  group('GestureDispatcher - pinchZoom', () {
    testWidgets(
      'pinch zoom dispatches two pointer sequences with unique device IDs',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.pinchZoom(
            const CoordinatesMatcher(200, 200),
            WidgetFinder(),
            const MarionetteConfiguration(),
            scale: 2.0,
          ),
        );
        await tester.pump();

        expect(events, isNotEmpty, reason: 'Should have dispatched events');

        // Should have exactly 2 PointerDownEvent (two fingers)
        final downEvents = events.whereType<PointerDownEvent>().toList();
        expect(downEvents, hasLength(2), reason: 'Two fingers should touch');

        // The two fingers should have different pointer IDs
        expect(
          downEvents[0].pointer,
          isNot(equals(downEvents[1].pointer)),
          reason: 'Each finger should have a unique pointer ID',
        );

        // Should have PointerMoveEvent for the zoom motion
        final moveEvents = events.whereType<PointerMoveEvent>().toList();
        expect(
          moveEvents.length,
          greaterThanOrEqualTo(2),
          reason: 'Should have move events for both fingers',
        );

        // Should have exactly 2 PointerUpEvent
        final upEvents = events.whereType<PointerUpEvent>().toList();
        expect(upEvents, hasLength(2), reason: 'Two fingers should lift');

        // Should clean up with PointerRemovedEvent
        final removedEvents = events.whereType<PointerRemovedEvent>().toList();
        expect(
          removedEvents,
          hasLength(2),
          reason: 'Each device should send PointerRemovedEvent',
        );
      },
    );

    testWidgets(
      'pinch zoom in moves fingers apart from center',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.pinchZoom(
            const CoordinatesMatcher(200, 200),
            WidgetFinder(),
            const MarionetteConfiguration(),
            scale: 2.0,
            startDistance: 100.0,
          ),
        );
        await tester.pump();

        final downEvents = events.whereType<PointerDownEvent>().toList();
        final upEvents = events.whereType<PointerUpEvent>().toList();

        // Start distance between fingers = 100
        final startDist =
            (downEvents[1].position.dx - downEvents[0].position.dx).abs();
        // End distance should be 200 (scale 2.0)
        final endDist =
            (upEvents[1].position.dx - upEvents[0].position.dx).abs();

        expect(
          startDist.round(),
          equals(100),
          reason: 'Initial finger distance should be 100px',
        );
        expect(
          endDist.round(),
          equals(200),
          reason: 'Final finger distance should be 200px (2x zoom)',
        );
      },
    );

    testWidgets(
      'pinch zoom out moves fingers closer together',
      timeout: _timeout,
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
        );

        final events = <PointerEvent>[];
        GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
        addTearDown(
          () => GestureBinding.instance.pointerRouter
              .removeGlobalRoute(events.add),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.pinchZoom(
            const CoordinatesMatcher(200, 200),
            WidgetFinder(),
            const MarionetteConfiguration(),
            scale: 0.5,
            startDistance: 200.0,
          ),
        );
        await tester.pump();

        final downEvents = events.whereType<PointerDownEvent>().toList();
        final upEvents = events.whereType<PointerUpEvent>().toList();

        final startDist =
            (downEvents[1].position.dx - downEvents[0].position.dx).abs();
        final endDist =
            (upEvents[1].position.dx - upEvents[0].position.dx).abs();

        expect(
          startDist.round(),
          equals(200),
          reason: 'Initial finger distance should be 200px',
        );
        expect(
          endDist.round(),
          equals(100),
          reason: 'Final finger distance should be 100px (0.5x zoom)',
        );
      },
    );
  });
}
