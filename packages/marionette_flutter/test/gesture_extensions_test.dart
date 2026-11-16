import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/gesture_extensions.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

void main() {
  group('swipeExtension', () {
    const configuration = MarionetteConfiguration();

    String invalidParamsDetail(MarionetteExtensionResult result) {
      expect(result, isA<MarionetteExtensionInvalidParams>());
      return (result as MarionetteExtensionInvalidParams).detail;
    }

    testWidgets(
      'reports missing coordinates even when startX is omitted',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));

        final result = await swipeExtension(
          const {'startY': '100', 'endX': '200', 'endY': '100'},
          gestureDispatcher: GestureDispatcher(),
          widgetFinder: WidgetFinder(),
          configuration: configuration,
        );

        expect(
          invalidParamsDetail(result),
          contains('Coordinate-based swipe requires all of'),
        );
      },
    );

    testWidgets(
      'rejects mixing coordinate-based and element-based parameters',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));

        final result = await swipeExtension(
          const {
            'startX': '0',
            'startY': '0',
            'endX': '100',
            'endY': '100',
            'direction': 'left',
          },
          gestureDispatcher: GestureDispatcher(),
          widgetFinder: WidgetFinder(),
          configuration: configuration,
        );

        expect(
          invalidParamsDetail(result),
          contains('Cannot mix coordinate-based swipe parameters'),
        );
      },
    );

    testWidgets(
      'rejects non-finite coordinate values',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));

        for (final badValue in const ['NaN', 'Infinity', '-Infinity']) {
          final result = await swipeExtension(
            {
              'startX': badValue,
              'startY': '100',
              'endX': '200',
              'endY': '100',
            },
            gestureDispatcher: GestureDispatcher(),
            widgetFinder: WidgetFinder(),
            configuration: configuration,
          );

          expect(
            invalidParamsDetail(result),
            contains('must be finite numbers'),
          );
        }
      },
    );

    testWidgets(
      'rejects non-positive or non-finite distance',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(key: ValueKey('target'), width: 100, height: 100),
            ),
          ),
        );

        for (final badDistance in const ['0', '-50', 'NaN', 'Infinity']) {
          final result = await swipeExtension(
            {
              'key': 'target',
              'direction': 'left',
              'distance': badDistance,
            },
            gestureDispatcher: GestureDispatcher(),
            widgetFinder: WidgetFinder(),
            configuration: configuration,
          );

          expect(
            invalidParamsDetail(result),
            contains('must be a positive number'),
          );
        }
      },
    );
  });
}
