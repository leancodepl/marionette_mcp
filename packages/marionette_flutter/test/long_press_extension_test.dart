import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/binding/extensions/gesture_extensions.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';

void main() {
  group('longPressExtension', () {
    testWidgets('rejects non-positive duration with invalidParams',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(key: ValueKey('target'), width: 100, height: 100),
          ),
        ),
      );

      for (final badDuration in const ['0', '-100']) {
        final result = await longPressExtension(
          {'key': 'target', 'duration': badDuration},
          gestureDispatcher: GestureDispatcher(),
          widgetFinder: WidgetFinder(),
          configuration: const MarionetteConfiguration(),
        );

        expect(result, isA<MarionetteExtensionInvalidParams>());
        expect(
          (result as MarionetteExtensionInvalidParams).detail,
          contains('must be a positive number'),
        );
      }
    });
  });
}
