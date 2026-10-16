// Captures the current native UI tree of a device as a test fixture.
//
// Usage (from packages/marionette_mcp):
//   dart run tool/capture_native_fixture.dart \
//     --platform android --serial emulator-5554 --name android28_permission
//   dart run tool/capture_native_fixture.dart \
//     --platform ios --udid <UDID> --name ios26_native_controls
//
// Writes test/native/fixtures/<platform>/<name>.xml (raw page source, server
// units) and <name>.json (screen in screenshot pixels, scale, foreground
// app, OS version). Navigate the app to the screen first. Fixtures are
// committed, so check them for personal data before adding them.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:marionette_mcp/src/native_service/android_native_connector.dart';
import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/webdriver_native_connector.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('platform', allowed: ['android', 'ios'], mandatory: true)
    ..addOption('serial', help: 'Android device serial.')
    ..addOption('udid', help: 'iOS Simulator UDID.')
    ..addOption('name', mandatory: true, help: 'Fixture file name (no ext).')
    ..addOption('os', help: 'OS version recorded in the metadata.')
    ..addOption(
      'out',
      defaultsTo: 'test/native/fixtures',
      help: 'Fixture root directory.',
    );
  final options = parser.parse(arguments);
  final platform = options['platform'] as String;
  final name = options['name'] as String;

  final WebDriverNativeConnector connector = platform == 'android'
      ? await AndroidNativeConnector.connect(
          serial: options['serial'] as String?,
        )
      : await IosNativeConnector.connect(udid: options['udid'] as String?);

  try {
    final source = await connector.client.getPageSource(connector.sessionId);
    final screen = await connector.getScreen();
    final foregroundApp = await connector.foregroundApp;

    final directory = Directory('${options['out']}/$platform')
      ..createSync(recursive: true);
    File('${directory.path}/$name.xml').writeAsStringSync(source);
    File('${directory.path}/$name.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
            'platform': platform,
            if (options['os'] != null) 'os': options['os'],
            'screen': screen.toJson(),
            'foregroundApp': foregroundApp,
          })}\n',
    );
    stdout.writeln(
      'Wrote ${directory.path}/$name.{xml,json} '
      '(${screen.width}x${screen.height}, scale ${screen.scale}, '
      'foreground $foregroundApp)',
    );
  } finally {
    await connector.dispose();
  }
}
