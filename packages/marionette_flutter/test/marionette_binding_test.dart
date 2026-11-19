import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/src/binding/marionette_binding.dart';

void main() {
  test(
    'ensureInitialized throws a clear FlutterError when another '
    'WidgetsBinding is already installed',
    () {
      // Simulates a plugin (e.g. Sentry's WidgetsFlutterBindingIntegration)
      // installing its own binding before MarionetteBinding gets a chance
      // to. See https://github.com/leancodepl/marionette_mcp/issues/96 —
      // previously this scenario made MarionetteBinding.ensureInitialized()
      // fail an internal Flutter assertion deep inside the binding
      // constructor instead of a clear, catchable error.
      TestWidgetsFlutterBinding.ensureInitialized();

      Object? caught;
      runZonedGuarded(
        MarionetteBinding.ensureInitialized,
        (error, _) => caught = error,
      );

      expect(caught, isA<FlutterError>());
      expect(caught.toString(), contains('already installed'));
      expect(
          caught.toString(), contains('MarionetteBinding.ensureInitialized()'));

      var factoryCalled = false;
      expect(
        () => MarionetteBindingMixin.ensureInitialized(() {
          factoryCalled = true;
          return _OtherBinding();
        }),
        throwsA(isA<FlutterError>()),
      );
      expect(factoryCalled, isFalse);
    },
  );
}

class _OtherBinding extends WidgetsFlutterBinding with MarionetteBindingMixin {}
