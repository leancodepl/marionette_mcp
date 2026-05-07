import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_logging/marionette_logging.dart';

import 'router.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized(
      MarionetteConfiguration(logCollector: LoggingLogCollector()),
    );
    _registerNavigationExtensions();
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  runApp(const ExampleApp());
}

void _registerNavigationExtensions() {
  // goToPage opts into the new dynamic-tool surface by declaring an
  // inputSchema — when an MCP client supports tools/list_changed, it
  // appears alongside the built-in marionette tools as
  // `appNavigation.goToPage` with full argument autocomplete.
  registerMarionetteExtension(
    name: 'appNavigation.goToPage',
    description: 'Navigates to a page by name.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'page': {
          'type': 'string',
          'description': 'Page name. One of: ${availablePages.keys.join(', ')}',
          'enum': availablePages.keys.toList(),
        },
      },
      'required': ['page'],
    },
    callback: (params) async {
      final page = params['page'];
      if (page == null) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: page',
        );
      }
      final path = availablePages[page];
      if (path == null) {
        return MarionetteExtensionResult.error(
          0,
          'Unknown page: $page. Available: ${availablePages.keys.join(', ')}',
        );
      }
      router.go(path);
      return MarionetteExtensionResult.success({'page': page, 'path': path});
    },
  );

  // No inputSchema — getPageInfo takes no arguments, but the absence of a
  // schema also exercises the schema-less code path. It stays reachable
  // through `call_custom_extension` and does not get promoted to a
  // first-class MCP tool.
  registerMarionetteExtension(
    name: 'appNavigation.getPageInfo',
    description: 'Returns the current page name, path, and a list of all '
        'available pages.',
    callback: (params) async {
      final location = router.routerDelegate.currentConfiguration.uri.path;
      final currentPage = availablePages.entries
              .where((e) => e.value == location)
              .map((e) => e.key)
              .firstOrNull ??
          'unknown';
      final pages = availablePages.keys.toList();
      return MarionetteExtensionResult.success({
        'currentPage': currentPage,
        'currentPath': location,
        'availablePages': pages,
      });
    },
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Marionette Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
