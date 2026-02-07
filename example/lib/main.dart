import 'dart:developer';

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
  registerExtension('ext.flutter.appNavigation.goToPage', (
    method,
    params,
  ) async {
    final page = params['page'];
    if (page == null) {
      return ServiceExtensionResponse.error(
        -1,
        'Missing required parameter: page',
      );
    }
    final path = availablePages[page];
    if (path == null) {
      return ServiceExtensionResponse.error(
        -1,
        'Unknown page: $page. Available: ${availablePages.keys.join(', ')}',
      );
    }
    router.go(path);
    return ServiceExtensionResponse.result(
      '{"status":"Success","page":"$page","path":"$path"}',
    );
  });

  registerExtension('ext.flutter.appNavigation.getPageInfo', (
    method,
    params,
  ) async {
    final location = router.routerDelegate.currentConfiguration.uri.path;
    final currentPage =
        availablePages.entries
            .where((e) => e.value == location)
            .map((e) => e.key)
            .firstOrNull ??
        'unknown';
    final pages = availablePages.keys.toList();
    return ServiceExtensionResponse.result(
      '{"status":"Success","currentPage":"$currentPage","currentPath":"$location","availablePages":${pages.map((p) => '"$p"').toList()}}',
    );
  });
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
