import 'package:flutter/widgets.dart';

/// Runtime overrides for the device configuration an app sees through
/// [MediaQuery].
///
/// A `null` field means "no override" — the platform value is used as-is.
@immutable
class DeviceConfigOverrides {
  const DeviceConfigOverrides({
    this.textScale,
    this.boldText,
    this.platformBrightness,
    this.disableAnimations,
  });

  /// Linear text scale, as in `TextScaler.linear(textScale)`.
  final double? textScale;

  /// The system "bold text" accessibility setting.
  final bool? boldText;

  /// The system light/dark appearance.
  final Brightness? platformBrightness;

  /// The system "reduce motion" accessibility setting.
  final bool? disableAnimations;

  /// Whether any field is overridden.
  bool get hasOverrides =>
      textScale != null ||
      boldText != null ||
      platformBrightness != null ||
      disableAnimations != null;

  Map<String, Object> toJson() => {
        if (textScale != null) 'textScale': textScale!,
        if (boldText != null) 'boldText': boldText!,
        if (platformBrightness != null)
          'platformBrightness': platformBrightness!.name,
        if (disableAnimations != null) 'disableAnimations': disableAnimations!,
      };

  @override
  bool operator ==(Object other) =>
      other is DeviceConfigOverrides &&
      other.textScale == textScale &&
      other.boldText == boldText &&
      other.platformBrightness == platformBrightness &&
      other.disableAnimations == disableAnimations;

  @override
  int get hashCode =>
      Object.hash(textScale, boldText, platformBrightness, disableAnimations);

  @override
  String toString() => 'DeviceConfigOverrides(${toJson()})';
}

/// Holds the device-configuration overrides requested over the VM service.
///
/// The service only stores state; applying it to the widget tree is the app's
/// decision, made by mounting a `MarionetteDeviceConfig` widget. That widget
/// attaches itself on mount and detaches on dispose, so [isAttached] tells
/// callers whether an override can currently take effect — without it, setting
/// one would silently do nothing.
class DeviceConfigService {
  /// Fires whenever the overrides change.
  final ValueNotifier<DeviceConfigOverrides> overrides =
      ValueNotifier(const DeviceConfigOverrides());

  /// The overrides currently in effect.
  DeviceConfigOverrides get current => overrides.value;

  int _attachedCount = 0;

  /// Whether at least one `MarionetteDeviceConfig` widget is mounted.
  bool get isAttached => _attachedCount > 0;

  /// Registers a mounted `MarionetteDeviceConfig` widget.
  void attach() => _attachedCount++;

  /// Unregisters a disposed `MarionetteDeviceConfig` widget.
  ///
  /// When the last one detaches the overrides are dropped, so a later remount
  /// starts from the platform defaults instead of resurrecting stale state.
  void detach() {
    _attachedCount--;
    if (_attachedCount <= 0) {
      _attachedCount = 0;
      overrides.value = const DeviceConfigOverrides();
    }
  }

  /// Applies the given values on top of the current overrides and returns the
  /// result. Fields left `null` keep whatever was set before.
  ///
  /// When [reset] is true the current overrides are dropped first, so a call
  /// that resets and sets in the same breath ends up with exactly the values
  /// passed here — that is also how a single field is reverted: reset, and
  /// re-state the ones worth keeping.
  DeviceConfigOverrides setOverrides({
    double? textScale,
    bool? boldText,
    Brightness? platformBrightness,
    bool? disableAnimations,
    bool reset = false,
  }) {
    final base = reset ? const DeviceConfigOverrides() : current;
    return overrides.value = DeviceConfigOverrides(
      textScale: textScale ?? base.textScale,
      boldText: boldText ?? base.boldText,
      platformBrightness: platformBrightness ?? base.platformBrightness,
      disableAnimations: disableAnimations ?? base.disableAnimations,
    );
  }
}
