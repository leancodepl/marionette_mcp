import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:marionette_flutter/src/binding/extension_schema.dart';
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
/// When [inputSchema] is provided, any property that declares a default is
/// filled in before [callback] runs if the caller omitted it — see
/// [mergeSchemaDefaults]. Built-in extensions pass no schema.
///
/// Uses [developer.registerExtension] directly, bypassing Flutter's
/// [BindingBase.registerServiceExtension].
void registerInternalMarionetteExtension({
  required String name,
  required MarionetteExtensionCallback callback,
  ExtensionInputSchema? inputSchema,
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
        result = await callback(mergeSchemaDefaults(inputSchema, parameters));
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
          final responseData = Map<String, Object?>.from(data);
          responseData['type'] = '_extensionType';
          responseData['method'] = method;
          responseData['status'] = 'Success';
          return developer.ServiceExtensionResponse.result(
            json.encode(responseData),
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

/// Returns [parameters] with any defaults declared by [schema] filled in for
/// keys the caller omitted. Values supplied by the caller always win.
///
/// VM service params arrive as a `Map<String, String>`, and the MCP server
/// stringifies provided values (e.g. `true` → `"true"`, `42` → `"42"`). To
/// keep callbacks from having to special-case where a value came from,
/// defaults are stringified the same way: a string default passes through,
/// everything else uses `toString()`. The `default` JSON Schema keyword is
/// only advisory to clients, so applying it here makes it authoritative
/// regardless of whether the client pre-fills it.
@visibleForTesting
Map<String, String> mergeSchemaDefaults(
  ExtensionInputSchema? schema,
  Map<String, String> parameters,
) {
  if (schema == null) return parameters;

  final withDefaults = <String, String>{};
  for (final entry in schema.properties.entries) {
    final json = entry.value.toJson();
    if (json.containsKey('default')) {
      final value = json['default'];
      withDefaults[entry.key] = value is String ? value : value.toString();
    }
  }

  if (withDefaults.isEmpty) return parameters;
  // Caller-supplied values override declared defaults.
  return withDefaults..addAll(parameters);
}
