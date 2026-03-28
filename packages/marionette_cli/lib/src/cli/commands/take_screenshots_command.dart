import 'dart:convert';
import 'dart:io';

import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';
import 'package:path/path.dart' as p;

class ScreenshotCommand extends InstanceCommand {
  ScreenshotCommand(this._registry) {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path for the screenshot PNG.',
        mandatory: true,
      )
      ..addFlag(
        'open',
        help: 'Open the screenshot after saving.',
        defaultsTo: false,
      );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'take-screenshots';

  @override
  String get description => 'Take a screenshot and save to file.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final outputPath = argResults!['output'] as String;
    final shouldOpen = argResults!['open'] as bool;

    final response = await connector.takeScreenshots();
    final screenshots = (response['screenshots'] as List<dynamic>)
        .cast<String>();

    if (screenshots.isEmpty) {
      stderr.writeln('No screenshots captured.');
      return 1;
    }

    final savedPaths = <String>[];

    for (var i = 0; i < screenshots.length; i++) {
      final path = screenshots.length == 1
          ? outputPath
          : _numberedPath(outputPath, i);

      final bytes = base64Decode(screenshots[i]);
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      savedPaths.add(path);
    }

    for (final saved in savedPaths) {
      stdout.writeln('Saved screenshot: $saved');
    }

    if (shouldOpen) {
      final opener = _openCommand();
      if (opener != null) {
        for (final saved in savedPaths) {
          await Process.run(opener, [saved]);
        }
      }
    }

    return 0;
  }

  /// Returns a numbered variant of a file path for multi-view screenshots.
  /// e.g., output.png -> output_1.png
  String _numberedPath(String path, int index) {
    if (index == 0) return path;
    final ext = p.extension(path);
    final base = p.withoutExtension(path);
    return '$base\_$index$ext';
  }

  String? _openCommand() {
    if (Platform.isLinux) return 'xdg-open';
    if (Platform.isMacOS) return 'open';
    if (Platform.isWindows) return 'start';
    return null;
  }
}
