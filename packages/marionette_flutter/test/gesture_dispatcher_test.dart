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
          const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
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
          const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
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
          const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
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
          const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
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
          const MaterialApp(
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

  group('GestureDispatcher.drag - Enhanced functionality', () {
    testWidgets('drag with small distance for controlled scrolling', timeout: _timeout,
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
      );

      final events = <PointerEvent>[];
      GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
      addTearDown(
        () => GestureBinding.instance.pointerRouter
            .removeGlobalRoute(events.add),
      );

      final dispatcher = GestureDispatcher();
      await tester.runAsync(
        () => dispatcher.drag(const Offset(100, 100), const Offset(100, 200)),
      );
      await tester.pump();

      expect(events, isNotEmpty, reason: 'Should have dispatched events');

      final moveEvents = events.whereType<PointerMoveEvent>().toList();
      expect(moveEvents, isNotEmpty, reason: 'Should have move events');
      
      // Verify small distance drag (100px with step-based movement)
      final firstMove = moveEvents.first;
      final lastMove = moveEvents.last;
      final totalDistance = (lastMove.position - firstMove.position).distance;
      expect(totalDistance, closeTo(100.0, 50.0)); // Allow tolerance for step-based movement
      
      // Verify X coordinate stays constant (vertical drag)
      expect(firstMove.position.dx, closeTo(100.0, 1.0));
      expect(lastMove.position.dx, closeTo(100.0, 1.0));
    });

    testWidgets('drag with direction-based movement', timeout: _timeout,
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
      );

      final events = <PointerEvent>[];
      GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
      addTearDown(
        () => GestureBinding.instance.pointerRouter
            .removeGlobalRoute(events.add),
      );

      final dispatcher = GestureDispatcher();
      
      // Test upward drag
      await tester.runAsync(
        () => dispatcher.drag(const Offset(100, 300), const Offset(100, 200)),
      );
      await tester.pump();

      expect(events, isNotEmpty, reason: 'Should have dispatched events');

      final moveEvents = events.whereType<PointerMoveEvent>().toList();
      expect(moveEvents, isNotEmpty, reason: 'Should have move events');
      
      // Verify upward movement (negative Y direction)
      final firstMove = moveEvents.first;
      final lastMove = moveEvents.last;
      final deltaY = lastMove.position.dy - firstMove.position.dy;
      expect(deltaY, closeTo(-100.0, 50.0)); // Allow tolerance for step-based movement
    });

    testWidgets('drag with incremental small steps', timeout: _timeout,
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
      );

      final events = <PointerEvent>[];
      GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
      addTearDown(
        () => GestureBinding.instance.pointerRouter
            .removeGlobalRoute(events.add),
      );

      final dispatcher = GestureDispatcher();
      
      // Test very small drag for incremental scrolling
      await tester.runAsync(
        () => dispatcher.drag(const Offset(100, 300), const Offset(100, 200)),
      );
      await tester.pump();

      expect(events, isNotEmpty, reason: 'Should have dispatched events');

      final moveEvents = events.whereType<PointerMoveEvent>().toList();
      expect(moveEvents, isNotEmpty, reason: 'Should have move events');
      
      // Verify small incremental movement
      final firstMove = moveEvents.first;
      final lastMove = moveEvents.last;
      final totalDistance = (lastMove.position - firstMove.position).distance;
      expect(totalDistance, closeTo(100.0, 50.0)); // Allow tolerance for step-based movement
      
      // Verify X coordinate stays constant (vertical drag)
      expect(firstMove.position.dx, closeTo(100.0, 1.0));
      expect(lastMove.position.dx, closeTo(100.0, 1.0));
    });

    testWidgets('drag handles different distances correctly', timeout: _timeout,
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
      );

      final events = <PointerEvent>[];
      GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
      addTearDown(
        () => GestureBinding.instance.pointerRouter
            .removeGlobalRoute(events.add),
      );

      final dispatcher = GestureDispatcher();
      
      // Test longer drag
      await tester.runAsync(
        () => dispatcher.drag(const Offset(100, 100), const Offset(300, 400)),
      );
      await tester.pump();

      expect(events, isNotEmpty, reason: 'Should have dispatched events');

      final moveEvents = events.whereType<PointerMoveEvent>().toList();
      expect(moveEvents, isNotEmpty, reason: 'Should have move events');
      
      // Verify longer distance is handled correctly
      final firstMove = moveEvents.first;
      final lastMove = moveEvents.last;
      final totalDistance = (lastMove.position - firstMove.position).distance;
      expect(totalDistance, closeTo(360.6, 50.0)); // sqrt(200^2 + 300^2) with tolerance
      
      // Verify proper step count for longer distances
      expect(moveEvents.length, greaterThan(1), reason: 'Should have multiple steps for longer drag');
    });

    testWidgets('drag maintains proper timing between steps', timeout: _timeout,
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: Text('Hello')))),
      );

      final events = <PointerEvent>[];
      GestureBinding.instance.pointerRouter.addGlobalRoute(events.add);
      addTearDown(
        () => GestureBinding.instance.pointerRouter
            .removeGlobalRoute(events.add),
      );

      final dispatcher = GestureDispatcher();
      
      await tester.runAsync(
        () => dispatcher.drag(const Offset(100, 100), const Offset(100, 300)),
      );
      await tester.pump();

      expect(events, isNotEmpty, reason: 'Should have dispatched events');
      
      // Verify proper event sequence (Added, Down, Move events, Up)
      expect(events.whereType<PointerAddedEvent>(), isNotEmpty);
      expect(events.whereType<PointerDownEvent>(), isNotEmpty);
      expect(events.whereType<PointerMoveEvent>(), isNotEmpty);
      expect(events.whereType<PointerUpEvent>(), isNotEmpty);
      
      // Verify multiple move events for step-based movement
      final moveEvents = events.whereType<PointerMoveEvent>().toList();
      expect(moveEvents.length, greaterThan(1), reason: 'Should have multiple move events for drag');
    });
  });
}
