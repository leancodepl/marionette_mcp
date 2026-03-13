import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

const _timeout = Timeout(Duration(seconds: 10));

void main() {
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
