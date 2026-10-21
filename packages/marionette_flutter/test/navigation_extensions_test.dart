import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/extensions/navigation_extensions.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';

void main() {
  /// A page-based Navigator that always refuses the pop, the same shape
  /// go_router produces when the route has local history or declares
  /// `onExit`. The returned `pushSecondPage` adds [secondPage] on top.
  Future<({GlobalKey<NavigatorState> key, void Function() pushSecondPage})>
      pumpRefusingNavigator(
    WidgetTester tester, {
    Widget secondPage = const SizedBox(),
  }) async {
    final key = GlobalKey<NavigatorState>();
    var pages = <Page<void>>[
      const MaterialPage<void>(key: ValueKey('page1'), child: SizedBox()),
    ];
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Navigator(
              key: key,
              pages: pages,
              // ignore: deprecated_member_use
              onPopPage: (route, result) => false,
            );
          },
        ),
      ),
    );

    return (
      key: key,
      pushSecondPage: () => rebuild(() {
            pages = [
              ...pages,
              MaterialPage<void>(
                  key: const ValueKey('page2'), child: secondPage),
            ];
          }),
    );
  }

  testWidgets(
    'waits for a running push transition to finish before popping, so a '
    'page-based Navigator that refuses the pop (the shape go_router '
    'produces) does not trip the mid-transition lifecycle assertion from '
    'https://github.com/leancodepl/marionette_mcp/issues/113',
    (tester) async {
      final navigator = await pumpRefusingNavigator(tester);

      navigator.pushSecondPage();
      await tester.pump();
      // Mid-transition: the default push animation runs for ~300ms, so the
      // pushed route's entry is still `pushing`, not `idle`, here.
      await tester.pump(const Duration(milliseconds: 50));

      final resultFuture = pressBackButton(
        handlePopRoute: navigator.key.currentState!.maybePop,
      );
      await tester.pumpAndSettle();

      expect(await resultFuture, isA<MarionetteExtensionSuccess>());
    },
  );

  testWidgets(
    'pops a settled route even while an unrelated animation keeps running',
    (tester) async {
      final navigator = await pumpRefusingNavigator(
        tester,
        secondPage: const Center(child: CircularProgressIndicator()),
      );

      navigator.pushSecondPage();
      await tester.pump();
      // Past the push transition; only the spinner is still animating.
      await tester.pump(const Duration(seconds: 1));

      var popCalled = false;
      final resultFuture = pressBackButton(
        handlePopRoute: () async {
          popCalled = true;
          return navigator.key.currentState!.maybePop();
        },
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(await resultFuture, isA<MarionetteExtensionSuccess>());
      expect(popCalled, isTrue);
    },
  );

  testWidgets(
    'returns an error instead of popping when a transition outlives the '
    'timeout',
    (tester) async {
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

      var popCalled = false;
      final resultFuture = pressBackButton(
        handlePopRoute: () async {
          popCalled = true;
          return true;
        },
        transitionTimeout: const Duration(milliseconds: 100),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(await resultFuture, isA<MarionetteExtensionError>());
      expect(popCalled, isFalse);
      await tester.pumpAndSettle();
    },
  );
}
