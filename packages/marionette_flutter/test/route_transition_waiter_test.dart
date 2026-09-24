import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/route_transition_waiter.dart';

void main() {
  const timeout = Duration(seconds: 5);

  /// Starts [waitForRouteTransitions] and reports whether it has completed,
  /// so tests can assert it is still waiting part-way through a transition.
  ({Future<bool> result, bool Function() isDone}) startWaiting({
    Duration timeout = timeout,
  }) {
    var done = false;
    final result = waitForRouteTransitions(timeout: timeout).then((value) {
      done = true;
      return value;
    });
    return (result: result, isDone: () => done);
  }

  testWidgets('resolves within a frame when no route is transitioning', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final waiting = startWaiting();
    await tester.pump();

    expect(waiting.isDone(), isTrue);
    expect(await waiting.result, isTrue);
  });

  testWidgets(
    'is not held up by a persistent animation that is not a route transition',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: CircularProgressIndicator())),
      );
      await tester.pump();
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));

      final waiting = startWaiting();
      // The spinner keeps a frame scheduled, so the waiter lets that one frame
      // run and then resolves, instead of waiting for the spinner to stop.
      await tester.pump(const Duration(milliseconds: 16));

      expect(waiting.isDone(), isTrue);
      expect(await waiting.result, isTrue);
    },
  );

  testWidgets('waits for an in-flight push transition to finish', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final waiting = startWaiting();
    await tester.pump(const Duration(milliseconds: 100));
    expect(waiting.isDone(), isFalse);

    await tester.pumpAndSettle();
    expect(await waiting.result, isTrue);
  });

  testWidgets(
    'waits for a page added to a page-based Navigator before its next frame',
    (tester) async {
      var pages = <Page<void>>[
        const MaterialPage<void>(key: ValueKey('first'), child: SizedBox()),
      ];
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Navigator(
                pages: pages,
                onDidRemovePage: (_) {},
              );
            },
          ),
        ),
      );

      // The same shape as a router applying a push on its next rebuild: the
      // new page isn't in the Navigator until the pending frame runs.
      rebuild(() {
        pages = [
          ...pages,
          const MaterialPage<void>(key: ValueKey('second'), child: SizedBox()),
        ];
      });

      final waiting = startWaiting();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(waiting.isDone(), isFalse);

      await tester.pumpAndSettle();
      expect(await waiting.result, isTrue);
    },
  );

  testWidgets('waits for a transition in a nested Navigator', (tester) async {
    final nestedKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          key: nestedKey,
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        ),
      ),
    );

    nestedKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final waiting = startWaiting();
    await tester.pump(const Duration(milliseconds: 100));
    expect(waiting.isDone(), isFalse);

    await tester.pumpAndSettle();
    expect(await waiting.result, isTrue);
  });

  testWidgets('reports false when a transition outlives the timeout', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );

    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(seconds: 10),
        pageBuilder: (_, __, ___) => const SizedBox(),
      ),
    );
    await tester.pump();

    final waiting = startWaiting(timeout: const Duration(milliseconds: 100));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(await waiting.result, isFalse);
    await tester.pumpAndSettle();
  });
}
