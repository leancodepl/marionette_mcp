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
  registerMarionetteExtension(
    name: 'appNavigation.goToPage',
    description:
        'Navigates to a page by name. '
        'Requires a "page" parameter with the page name.',
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

  registerMarionetteExtension(
    name: 'appNavigation.getPageInfo',
    description:
        'Returns the current page name, path, and a list of all '
        'available pages.',
    callback: (params) async {
      final location = router.routerDelegate.currentConfiguration.uri.path;
      final currentPage =
          availablePages.entries
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
