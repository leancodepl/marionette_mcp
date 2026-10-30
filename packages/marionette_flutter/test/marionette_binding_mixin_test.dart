import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

class _CombinedBinding extends WidgetsFlutterBinding
    with MarionetteBindingMixin {}

void main() {
  test('a custom binding mixing in MarionetteBindingMixin is installed with '
      'the latched configuration', () {
    const configuration = MarionetteConfiguration(
      maxScreenshotSize: Size(100, 100),
    );
    MarionetteBindingMixin.latchConfiguration(configuration);
    final binding = _CombinedBinding();

    expect(MarionetteBindingMixin.instance, same(binding));
    expect(WidgetsBinding.instance, same(binding));
    expect(binding.configuration, same(configuration));
    expect(MarionetteBindingMixin.maybeDeviceConfigService, isNotNull);
  });
}
