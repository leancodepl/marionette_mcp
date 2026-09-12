import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

import 'multi_view_test_helpers.dart';

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
      'doubleTap should dispatch two complete tap sequences',
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
        await tester.runAsync(() => dispatcher.doubleTap(
              const CoordinatesMatcher(100, 100),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        // Two taps = 2x (Added, Down, Up, Removed)
        final downEvents = events.whereType<PointerDownEvent>().toList();
        final upEvents = events.whereType<PointerUpEvent>().toList();
        final removedEvents = events.whereType<PointerRemovedEvent>().toList();

        expect(downEvents, hasLength(2),
            reason: 'Double tap should have 2 PointerDownEvents');
        expect(upEvents, hasLength(2),
            reason: 'Double tap should have 2 PointerUpEvents');
        expect(removedEvents, hasLength(2),
            reason: 'Double tap should have 2 PointerRemovedEvents');

        // Each tap should use a different pointer ID
        expect(downEvents[0].pointer, isNot(equals(downEvents[1].pointer)),
            reason: 'Each tap should use a unique pointer ID');

        // All events should use non-zero device ID
        for (final event in events) {
          expect(event.device, isNot(equals(0)));
        }
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

  group('GestureDispatcher - secondaryTap', () {
    testWidgets(
      'secondaryTap dispatches a mouse pointer with the secondary button',
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
        await tester.runAsync(() => dispatcher.secondaryTap(
              const CoordinatesMatcher(100, 100),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

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
            event.kind,
            equals(PointerDeviceKind.mouse),
            reason: '${event.runtimeType} should be a mouse pointer',
          );
          expect(
            event.device,
            isNot(equals(0)),
            reason: '${event.runtimeType} should use a unique device id, '
                'not 0 which is the real desktop cursor',
          );
        }

        expect(
          downEvents.single.buttons,
          equals(kSecondaryButton),
          reason: 'PointerDownEvent should press the secondary button',
        );
        expect(
          upEvents.single.buttons,
          equals(0),
          reason: 'PointerUpEvent should release all buttons',
        );
      },
    );

    testWidgets(
      'secondaryTap actually triggers onSecondaryTap on a widget',
      timeout: _timeout,
      (WidgetTester tester) async {
        var secondaryTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GestureDetector(
                  onSecondaryTap: () => secondaryTapped = true,
                  child: const SizedBox(
                    width: 100,
                    height: 100,
                    child: Text('target'),
                  ),
                ),
              ),
            ),
          ),
        );

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.secondaryTap(
              const TextMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        expect(
          secondaryTapped,
          isTrue,
          reason: 'GestureDetector.onSecondaryTap should have fired',
        );
      },
    );
  });

  group('GestureDispatcher - multi-view', () {
    testWidgets(
      'tap by coordinates reaches the rendered view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var tapped = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(onTap: () => tapped = true),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.tap(
              const CoordinatesMatcher(400, 300),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(
          tapped,
          isTrue,
          reason: 'A coordinate tap must reach the widget in the rendered '
              'view, not the implicit view that renders nothing',
        );
      },
    );

    testWidgets(
      'tap by key reaches the element\'s own view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var tapped = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(
            key: const ValueKey('target'),
            onTap: () => tapped = true,
          ),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.tap(
              const KeyMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(
          tapped,
          isTrue,
          reason: 'An element tap must be dispatched into the view the '
              'element is mounted in',
        );
      },
    );

    testWidgets(
      'doubleTap reaches the element\'s own view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var doubleTapped = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(
            key: const ValueKey('target'),
            onDoubleTap: () => doubleTapped = true,
          ),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.doubleTap(
              const KeyMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(doubleTapped, isTrue);
      },
    );

    testWidgets(
      'longPress reaches the element\'s own view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var longPressed = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(
            key: const ValueKey('target'),
            onLongPress: () => longPressed = true,
          ),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.longPress(
              const KeyMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
              duration: const Duration(milliseconds: 600),
            ));
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(longPressed, isTrue);
      },
    );

    testWidgets(
      'secondaryTap reaches the element\'s own view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var secondaryTapped = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(
            key: const ValueKey('target'),
            onSecondaryTap: () => secondaryTapped = true,
          ),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.secondaryTap(
              const KeyMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
            ));
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(secondaryTapped, isTrue);
      },
    );

    testWidgets(
      'pinchZoom reaches the element\'s own view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var scaled = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(
            key: const ValueKey('target'),
            onScaleUpdate: (details) => scaled = true,
          ),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.pinchZoom(
              const KeyMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
              scale: 2,
            ));
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(
          scaled,
          isTrue,
          reason: 'The pinch must be recognised by the widget in the '
              'non-implicit view, not merely be tagged with its view id',
        );
      },
    );

    testWidgets(
      'swipe reaches the element\'s own view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var panned = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(
            key: const ValueKey('target'),
            onPanUpdate: (details) => panned = true,
          ),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(() => dispatcher.swipe(
              const KeyMatcher('target'),
              WidgetFinder(),
              const MarionetteConfiguration(),
              direction: 'up',
              distance: 100,
            ));
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(
          panned,
          isTrue,
          reason: 'The swipe must be recognised by the widget in the '
              'non-implicit view, not merely be tagged with its view id',
        );
      },
    );

    testWidgets(
      'drag by coordinates reaches the rendered view',
      timeout: _timeout,
      (WidgetTester tester) async {
        var panned = false;
        final fakeView = await _pumpInFakeView(
          tester,
          _gestureTarget(onPanUpdate: (details) => panned = true),
        );
        final events = _recordPointerEvents();

        final dispatcher = GestureDispatcher();
        await tester.runAsync(
          () => dispatcher.drag(const Offset(400, 350), const Offset(400, 250)),
        );
        await tester.pump();

        _expectAllInView(events, fakeView);
        expect(
          panned,
          isTrue,
          reason: 'A coordinate drag must be recognised by the widget in the '
              'rendered view, not merely be tagged with its view id',
        );
      },
    );
  });
}

/// Mounts [child] as the whole content of a non-implicit view.
///
/// `wrapWithView: false` leaves the implicit view without a `RenderView`, which
/// is the shape of an app rendering through the desktop windowing API.
Future<FakeView> _pumpInFakeView(WidgetTester tester, Widget child) async {
  final fakeView = FakeView(tester.view);
  await tester.pumpWidget(
    wrapWithView: false,
    View(view: fakeView, child: child),
  );
  return fakeView;
}

/// A centered gesture target that is hit-testable on its own.
Widget _gestureTarget({
  Key? key,
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
  VoidCallback? onLongPress,
  VoidCallback? onSecondaryTap,
  GestureDragUpdateCallback? onPanUpdate,
  GestureScaleUpdateCallback? onScaleUpdate,
}) {
  return Center(
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      onPanUpdate: onPanUpdate,
      onScaleUpdate: onScaleUpdate,
      child: const SizedBox(width: 200, height: 200),
    ),
  );
}

/// Collects every pointer event the binding routes, for the length of the test.
List<PointerEvent> _recordPointerEvents() {
  final events = <PointerEvent>[];
  void record(PointerEvent event) => events.add(event);

  GestureBinding.instance.pointerRouter.addGlobalRoute(record);
  addTearDown(
    () => GestureBinding.instance.pointerRouter.removeGlobalRoute(record),
  );
  return events;
}

void _expectAllInView(List<PointerEvent> events, FakeView view) {
  expect(events, isNotEmpty, reason: 'Should have dispatched events');
  for (final event in events) {
    expect(
      event.viewId,
      equals(view.viewId),
      reason: '${event.runtimeType} should carry the view id of the view it '
          'is meant for, otherwise it hit-tests against a view that renders '
          'nothing',
    );
  }
}
