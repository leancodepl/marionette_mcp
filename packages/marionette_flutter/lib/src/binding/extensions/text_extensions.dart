import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/text_input_simulator.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Registers text-input `marionette.*` extensions: enterText.
void registerTextExtensions({
  required TextInputSimulator textInputSimulator,
  required MarionetteConfiguration configuration,
}) {
  registerInternalMarionetteExtension(
    name: 'marionette.enterText',
    callback: (params) async {
      final matcher = WidgetMatcher.fromJson(params);
      final input = params['input'];

      if (input == null) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: input',
        );
      }

      await textInputSimulator.enterText(matcher, input, configuration);

      return MarionetteExtensionResult.success({
        'message': 'Entered text into element matching: ${matcher.toJson()}',
      });
    },
  );
}
