import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  test('concrete initializer preserves configuration and repeat identity', () {
    const configuration = MarionetteConfiguration(
      maxScreenshotSize: Size(320, 240),
    );

    final first = MarionetteBinding.ensureInitialized(configuration);
    final second = MarionetteBinding.ensureInitialized(
      const MarionetteConfiguration(),
    );

    expect(first.configuration, same(configuration));
    expect(second, same(first));
    expect(WidgetsBinding.instance, same(first));
  });
}
