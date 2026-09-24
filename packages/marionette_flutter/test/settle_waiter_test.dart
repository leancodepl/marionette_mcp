import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/services/settle_waiter.dart';

void main() {
  testWidgets(
    'resolves immediately when nothing is animating',
    (tester) async {
      await tester.pumpWidget(const SizedBox());

      final settled = await waitForNoTransientCallbacks(
        timeout: const Duration(seconds: 5),
      );

      expect(settled, isTrue);
    },
  );

  testWidgets(
    'resolves true once a running animation finishes within the timeout',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: CircularProgressIndicator())),
      );
      await tester.pump();
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));

      final settledFuture = waitForNoTransientCallbacks(
        timeout: const Duration(seconds: 5),
      );

      // Stop the only ticker in the tree, then let a frame flush so
      // `transientCallbackCount` drops back to zero.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(await settledFuture, isTrue);
    },
  );

  testWidgets(
    'reports not settled once a persistent ticker outlives the timeout',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: CircularProgressIndicator())),
      );
      await tester.pump();
      expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));

      final settledFuture = waitForNoTransientCallbacks(
        timeout: const Duration(milliseconds: 100),
      );

      // The indicator's animation controller repeats forever, so pumping
      // past the timeout never brings transientCallbackCount to zero.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(await settledFuture, isFalse);
    },
  );
}
