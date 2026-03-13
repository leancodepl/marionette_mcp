import 'package:flutter/widgets.dart';

/// Manages runtime overrides for device configuration (text scale, bold text).
///
/// Overrides are applied via a [DeviceConfigWrapper] widget injected at the
/// root of the widget tree through [MarionetteBinding.wrapWithDefaultView].
/// Calling [setOverrides] updates the values and triggers a rebuild.
class DeviceConfigService {
  /// Notifier that fires whenever any override changes.
  final ValueNotifier<DeviceConfigOverrides> overrides =
      ValueNotifier(const DeviceConfigOverrides());

  /// Applies new overrides, merging with existing ones.
  ///
  /// Pass a value to set it. Pass [resetTextScaleFactor] or [resetBoldText]
  /// as `true` to clear that override and revert to the platform default.
  DeviceConfigOverrides setOverrides({
    double? textScaleFactor,
    bool? boldText,
    bool resetTextScaleFactor = false,
    bool resetBoldText = false,
  }) {
    overrides.value = DeviceConfigOverrides(
      textScaleFactor: resetTextScaleFactor
          ? null
          : (textScaleFactor ?? overrides.value.textScaleFactor),
      boldText: resetBoldText ? null : (boldText ?? overrides.value.boldText),
    );
    return overrides.value;
  }

  /// Returns the current active overrides.
  DeviceConfigOverrides get current => overrides.value;
}

/// Holds the current device config override values.
///
/// Fields that are `null` fall through to the platform default.
class DeviceConfigOverrides {
  const DeviceConfigOverrides({this.textScaleFactor, this.boldText});

  /// If non-null, overrides the platform text scale factor.
  final double? textScaleFactor;

  /// If non-null, overrides the platform bold-text accessibility setting.
  final bool? boldText;

  bool get hasOverrides => textScaleFactor != null || boldText != null;

  Map<String, dynamic> toJson() => {
        if (textScaleFactor != null) 'textScaleFactor': textScaleFactor,
        if (boldText != null) 'boldText': boldText,
      };
}

/// Widget injected at the root of the tree via
/// [MarionetteBinding.wrapWithDefaultView].
///
/// Listens to [DeviceConfigService.overrides] and applies [MediaQuery]
/// overrides when active. The [MediaQuery] inserted here becomes the
/// `platformData` source for [MaterialApp]'s internal
/// `_MediaQueryFromView`, so the override propagates through the entire
/// widget tree.
class DeviceConfigWrapper extends StatelessWidget {
  const DeviceConfigWrapper({
    required this.overrides,
    required this.child,
    super.key,
  });

  final ValueNotifier<DeviceConfigOverrides> overrides;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DeviceConfigOverrides>(
      valueListenable: overrides,
      builder: (context, config, child) {
        if (!config.hasOverrides) return child!;

        final baseData = MediaQuery.maybeOf(context) ??
            MediaQueryData.fromView(View.of(context));

        final data = baseData.copyWith(
          textScaler: config.textScaleFactor != null
              ? TextScaler.linear(config.textScaleFactor!)
              : baseData.textScaler,
          boldText: config.boldText ?? baseData.boldText,
        );

        return MediaQuery(data: data, child: child!);
      },
      child: child,
    );
  }
}
