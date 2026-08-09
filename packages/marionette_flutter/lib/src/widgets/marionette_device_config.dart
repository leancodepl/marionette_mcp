import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_binding.dart';
import 'package:marionette_flutter/src/services/device_config_service.dart';

/// Lets Marionette override the device configuration — text scale, bold text,
/// light/dark appearance — for the subtree below it.
///
/// This is opt-in: Marionette never inserts it for you, so an app that doesn't
/// mount it keeps its widget tree exactly as written. Wrap the root widget to
/// enable the `set_device_config` tool:
///
/// ```dart
/// void main() {
///   MarionetteBinding.ensureInitialized();
///   runApp(const MarionetteDeviceConfig(child: MyApp()));
/// }
/// ```
///
/// The overrides are applied through a [MediaQuery] slotted between the app
/// and the live one `View` installs above it, so every `MediaQuery.of` below
/// resolves to the overridden data — `MaterialApp`'s theme resolution
/// included. `WidgetsApp` introduces no [MediaQuery] of its own; the `View`
/// widget is the only source.
///
/// When Marionette is not active — a release build, or a binding that was
/// never initialized — this builds [child] unchanged.
class MarionetteDeviceConfig extends StatefulWidget {
  const MarionetteDeviceConfig({
    required this.child,
    this.service,
    super.key,
  });

  /// The service to take overrides from.
  ///
  /// Defaults to the binding's, which is `null` when no [MarionetteBinding]
  /// was installed — in that case this widget is a pass-through. Mainly a
  /// testing seam.
  final DeviceConfigService? service;

  final Widget child;

  @override
  State<MarionetteDeviceConfig> createState() => _MarionetteDeviceConfigState();
}

class _MarionetteDeviceConfigState extends State<MarionetteDeviceConfig> {
  DeviceConfigService? _service;

  @override
  void initState() {
    super.initState();
    _service = _resolveService()?..attach();
  }

  @override
  void didUpdateWidget(MarionetteDeviceConfig oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.service != oldWidget.service) {
      _service?.detach();
      _service = _resolveService()?..attach();
    }
  }

  @override
  void dispose() {
    _service?.detach();
    super.dispose();
  }

  DeviceConfigService? _resolveService() =>
      widget.service ?? MarionetteBinding.maybeDeviceConfigService;

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return widget.child;
    }

    return ValueListenableBuilder<DeviceConfigOverrides>(
      valueListenable: service.overrides,
      child: widget.child,
      // The MediaQuery goes in unconditionally, even with nothing overridden.
      // Inserting it only once an override arrives would change the shape of
      // the tree below this point, and Flutter answers a shape change by
      // tearing the subtree down and building it again — the app would lose
      // its navigation stack and every State below it the moment an override
      // was applied, and again when it was reset.
      //
      // With no overrides the copy is field-for-field equal to the parent
      // data, so MediaQuery.updateShouldNotify sees no change and nothing
      // below rebuilds.
      builder: (context, config, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: config.textScale != null
              ? TextScaler.linear(config.textScale!)
              : null,
          boldText: config.boldText,
          platformBrightness: config.platformBrightness,
        ),
        child: child!,
      ),
    );
  }
}
