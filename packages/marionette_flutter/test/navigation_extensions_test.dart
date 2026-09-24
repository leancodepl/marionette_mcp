import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/extensions/navigation_extensions.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';

void main() {
  testWidgets(
    'waits for a running push transition to settle before popping, so a '
    'page-based Navigator that refuses the pop (the shape go_router '
    'produces) does not trip the mid-transition lifecycle assertion from '
    'https://github.com/leancodepl/marionette_mcp/issues/113',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      var pages = <Page<void>>[
        const MaterialPage<void>(
          key: ValueKey('page1'),
          child: SizedBox(key: Key('page1-content')),
        ),
      ];

      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Navigator(
                key: navigatorKey,
                pages: pages,
                // A page-based Navigator that always refuses the pop, the
                // same shape go_router produces when the route has local
                // history or declares `onExit`.
                // ignore: deprecated_member_use
                onPopPage: (route, result) => false,
              );
            },
          ),
        ),
      );

      rebuild(() {
        pages = [
          ...pages,
          const MaterialPage<void>(
            key: ValueKey('page2'),
            child: SizedBox(key: Key('page2-content')),
          ),
        ];
      });
      await tester.pump();
      // Mid-transition: the default push animation runs for ~300ms, so the
      // pushed route's entry is still `pushing`, not `idle`, here.
      await tester.pump(const Duration(milliseconds: 50));

      final resultFuture = pressBackButton(
        handlePopRoute: navigatorKey.currentState!.maybePop,
      );

      // Let the push transition finish so the settle wait inside
      // pressBackButton can complete.
      await tester.pumpAndSettle();

      final result = await resultFuture;

      expect(result, isA<MarionetteExtensionSuccess>());
    },
  );

  testWidgets(
    'returns an error instead of popping when the app never settles',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: CircularProgressIndicator())),
      );
      await tester.pump();

      var popCalled = false;
      final resultFuture = pressBackButton(
        handlePopRoute: () async {
          popCalled = true;
          return true;
        },
        settleTimeout: const Duration(milliseconds: 100),
      );

      // The indicator's animation controller repeats forever, so the app
      // never settles no matter how long we keep pumping.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final result = await resultFuture;

      expect(result, isA<MarionetteExtensionError>());
      expect(popCalled, isFalse);
    },
  );
}
