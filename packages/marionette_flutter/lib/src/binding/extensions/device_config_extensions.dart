import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/extensions/extension_helpers.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/device_config_service.dart';

/// Help text returned by `marionette.setDeviceConfig` when the app has not
/// mounted a `MarionetteDeviceConfig` widget. Carries setup instructions for
/// the user, mirroring the log-collector help in `marionette.getLogs`.
const _deviceConfigMissingHelp =
    '''Device config overrides are not available in this app.

Overriding text scale or accessibility settings needs a MediaQuery above your
app, and Marionette does not insert one for you — wrap your root widget:

  runApp(
    const MarionetteDeviceConfig(
      child: MyApp(),
    ),
  );

This lives in main(), which a hot reload does not re-run — hot restart the app
after adding it.

See https://pub.dev/packages/marionette_flutter for more details.''';

/// Registers the device-configuration `marionette.*` extension:
/// setDeviceConfig.
void registerDeviceConfigExtensions({
  required DeviceConfigService deviceConfigService,
}) {
  registerInternalMarionetteExtension(
    name: 'marionette.setDeviceConfig',
    callback: (params) async => setDeviceConfig(params, deviceConfigService),
  );
}

/// Handles a `marionette.setDeviceConfig` call: validates the params, checks
/// that the app opted in, and applies the overrides.
///
/// Extracted from the callback so every coercion and validation branch can be
/// exercised without a VM service.
@visibleForTesting
MarionetteExtensionResult setDeviceConfig(
  Map<String, String> params,
  DeviceConfigService service,
) {
  // Overrides only take effect if the app mounted a MarionetteDeviceConfig
  // widget. Fail loud with setup instructions rather than reporting success
  // on what would be a no-op.
  if (!service.isAttached) {
    return MarionetteExtensionResult.error(0, _deviceConfigMissingHelp);
  }

  final reset = parseOptionalBool(params, 'reset');
  if (reset.error case final error?) {
    return error;
  }

  final textScale =
      parsePositiveDouble(params, 'textScale', defaultValue: null);
  if (textScale.error case final error?) {
    return error;
  }

  final boldText = parseOptionalBool(params, 'boldText');
  if (boldText.error case final error?) {
    return error;
  }

  final disableAnimations = parseOptionalBool(params, 'disableAnimations');
  if (disableAnimations.error case final error?) {
    return error;
  }

  final platformBrightness = _parseBrightness(params, 'platformBrightness');
  if (platformBrightness.error case final error?) {
    return error;
  }

  final setsAnyField = textScale.value != null ||
      boldText.value != null ||
      disableAnimations.value != null ||
      platformBrightness.value != null;

  // `reset: false` on its own would otherwise report success having changed
  // nothing.
  if (!setsAnyField && reset.value != true) {
    return MarionetteExtensionResult.invalidParams(
      'At least one parameter is required: textScale, boldText, '
      'platformBrightness, disableAnimations, or reset=true',
    );
  }

  final applied = service.setOverrides(
    textScale: textScale.value,
    boldText: boldText.value,
    disableAnimations: disableAnimations.value,
    platformBrightness: platformBrightness.value,
    reset: reset.value ?? false,
  );

  return MarionetteExtensionResult.success({
    'message': setsAnyField
        ? 'Device config updated'
        : 'Device config reset to platform defaults',
    'overrides': applied.toJson(),
  });
}

({Brightness? value, MarionetteExtensionResult? error}) _parseBrightness(
  Map<String, String> params,
  String key,
) {
  final raw = params[key];
  if (raw == null) {
    return (value: null, error: null);
  }
  return switch (raw) {
    'light' => (value: Brightness.light, error: null),
    'dark' => (value: Brightness.dark, error: null),
    _ => (
        value: null,
        error: MarionetteExtensionResult.invalidParams(
          'Parameter "$key" must be "light" or "dark", got "$raw"',
        ),
      ),
  };
}
