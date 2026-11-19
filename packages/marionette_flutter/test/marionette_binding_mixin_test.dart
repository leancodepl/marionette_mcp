import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

class _CombinedBinding extends WidgetsFlutterBinding
    with _OtherBindingMixin, MarionetteBindingMixin {
  _CombinedBinding(this._configuration);

  final MarionetteConfiguration _configuration;

  @override
  MarionetteConfiguration get configuration => _configuration;
}

void main() {
  test(
      'a custom binding mixing in MarionetteBindingMixin is installed with '
      'its configuration', () {
    const configuration = MarionetteConfiguration(
      maxScreenshotSize: Size(100, 100),
    );
    final binding = MarionetteBindingMixin.ensureInitialized(
      () => _CombinedBinding(configuration),
    );

    expect(MarionetteBindingMixin.instance, same(binding));
    expect(WidgetsBinding.instance, same(binding));
    expect(binding.configuration, same(configuration));
    expect(MarionetteBindingMixin.maybeDeviceConfigService, isNotNull);
    expect(binding.instancesInitialized, isTrue);
    expect(binding.extensionsInitialized, isTrue);
    final calls = <int>[];
    final second = MarionetteBindingMixin.ensureInitialized(() {
      calls.add(1);
      return _CombinedBinding(const MarionetteConfiguration());
    });
    expect(second, same(binding));
    expect(calls, isEmpty);

    expect(
      () => MarionetteBinding.instance,
      throwsA(
        predicate<FlutterError>(
          (error) =>
              error.toString().contains('not MarionetteBinding') &&
              error.toString().contains('MarionetteBindingMixin.instance'),
        ),
      ),
    );

    final service = MarionetteBindingMixin.maybeDeviceConfigService!;
    expect(service.setOverrides(textScale: 1.5).textScale, 1.5);
  });
}

mixin _OtherBindingMixin on WidgetsBinding {
  bool instancesInitialized = false;
  bool extensionsInitialized = false;

  @override
  void initInstances() {
    super.initInstances();
    instancesInitialized = true;
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();
    extensionsInitialized = true;
  }
}
