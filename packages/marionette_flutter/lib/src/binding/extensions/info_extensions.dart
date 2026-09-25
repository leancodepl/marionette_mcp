import 'dart:convert';

import 'package:marionette_flutter/src/binding/marionette_extension_result.dart';
import 'package:marionette_flutter/src/binding/register_extension.dart';
import 'package:marionette_flutter/src/binding/register_extension_internal.dart';
import 'package:marionette_flutter/src/services/element_tree_finder.dart';
import 'package:marionette_flutter/src/services/log_store.dart';
import 'package:marionette_flutter/src/version.g.dart' as v;

/// Current wire schema for the interactive-elements response.
const interactiveElementsSchemaVersion = 1;

/// Builds a versioned response while safely snapshotting optional app context.
Map<String, dynamic> buildInteractiveElementsResponse(
  List<Map<String, dynamic>> elements, {
  Map<String, Object?> Function()? contextProvider,
}) {
  final context = _readContext(contextProvider);
  return <String, dynamic>{
    'schemaVersion': interactiveElementsSchemaVersion,
    if (context != null) 'context': context,
    'elements': elements,
  };
}

/// Help text returned by `marionette.getLogs` when no log collector has been
/// configured. Carries setup instructions for the user.
const _logCollectorMissingHelp = '''Log collection is not configured.

To enable log collection, provide a LogCollector via MarionetteConfiguration:

Option 1: Using the "logging" package (pub.dev/packages/logging)
  - Add dependency: flutter pub add marionette_logging
  - Initialize: MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: LoggingLogCollector()),
    );

Option 2: Using the "logger" package (pub.dev/packages/logger)
  - Add dependency: flutter pub add marionette_logger
  - Initialize: final collector = LoggerLogCollector();
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: collector),
    );
    final logger = Logger(output: MultiOutput([ConsoleOutput(), collector]));

Option 3: Using PrintLogCollector for custom logging
  - Initialize: final collector = PrintLogCollector();
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: collector),
    );
  - Call collector.addLog(message) from your logging listener.

See https://pub.dev/packages/marionette_flutter for more details.''';

/// Registers read-only informational `marionette.*` extensions.
///
/// [logStoreProvider] is read at call time (not capture time) because the
/// log store can be created lazily when the binding is configured with a
/// log collector.
void registerInfoExtensions({
  required ElementTreeFinder elementTreeFinder,
  required LogStore? Function() logStoreProvider,
  Map<String, Object?> Function()? contextProvider,
}) {
  registerInternalMarionetteExtension(
    name: 'marionette.getVersion',
    callback: (params) async {
      return MarionetteExtensionResult.success({'version': v.version});
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.interactiveElements',
    callback: (params) async {
      final elements = elementTreeFinder.findInteractiveElements();
      return MarionetteExtensionResult.success(
        buildInteractiveElementsResponse(
          elements,
          contextProvider: contextProvider,
        ),
      );
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.getLogs',
    callback: (params) async {
      final logStore = logStoreProvider();
      if (logStore == null) {
        return MarionetteExtensionResult.error(0, _logCollectorMissingHelp);
      }
      final logs = logStore.getLogs();
      return MarionetteExtensionResult.success({
        'logs': logs,
        'count': logs.length,
      });
    },
  );

  registerInternalMarionetteExtension(
    name: 'marionette.listExtensions',
    callback: (params) async {
      return MarionetteExtensionResult.success({
        'extensions': [
          for (final ext in customExtensionRegistry)
            {
              'name': ext.name,
              if (ext.description != null) 'description': ext.description,
              if (ext.inputSchema != null)
                'inputSchema': ext.inputSchema!.toJson(),
            },
        ],
      });
    },
  );
}

Map<String, Object?>? _readContext(Map<String, Object?> Function()? provider) {
  if (provider == null) {
    return null;
  }
  try {
    final context = Map<String, Object?>.unmodifiable(provider());
    if (context.isEmpty) {
      return null;
    }
    jsonEncode(context);
    return context;
  } on Object {
    // Context is optional and must never make element discovery unavailable.
    return null;
  }
}
