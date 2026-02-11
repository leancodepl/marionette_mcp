import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension.dart';

/// Registers a built-in Marionette service extension.
///
/// This is intended for internal use by [MarionetteBinding] only. Unlike
/// [registerMarionetteExtension], it does **not** add the extension to the
/// [customExtensionRegistry].
///
/// The `ext.flutter.` prefix is added automatically to [name].
///
/// Uses [developer.registerExtension] directly, bypassing Flutter's
/// [BindingBase.registerServiceExtension].
void registerInternalMarionetteExtension({
  required String name,
  required MarionetteExtensionCallback callback,
}) {
  final methodName = 'ext.flutter.$name';

  developer.registerExtension(
    methodName,
    (method, parameters) async {
      // Wait for the outer event loop, same as Flutter's
      // registerServiceExtension, to avoid handling extensions in the middle
      // of a frame.
      await Future<void>.delayed(Duration.zero);

      late final MarionetteExtensionResult result;
      try {
        result = await callback(parameters);
      } on ArgumentError catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          e.message?.toString() ?? e.toString(),
        );
      } catch (exception, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: exception,
            stack: stack,
            context: ErrorDescription(
              'during a service extension callback for "$method"',
            ),
          ),
        );

        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          json.encode(<String, String>{
            'exception': exception.toString(),
            'stack': stack.toString(),
            'method': method,
          }),
        );
      }

      switch (result) {
        case MarionetteExtensionSuccess(:final data):
          data['type'] = '_extensionType';
          data['method'] = method;
          data['status'] = 'Success';
          return developer.ServiceExtensionResponse.result(
            json.encode(data),
          );
        case MarionetteExtensionError(:final code, :final detail):
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionErrorMin + code,
            detail,
          );
        case MarionetteExtensionInvalidParams(:final detail):
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            detail,
          );
      }
    },
  );
}
