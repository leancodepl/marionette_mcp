import 'dart:convert';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart';

/// Environment variable that enables writing screenshot PNGs to disk.
///
/// When unset or empty, screenshots are returned inline only (no files written).
const screenshotsDirEnvKey = 'MARIONETTE_SCREENSHOTS_DIR';

/// Writes a base64-encoded PNG to disk when a screenshots directory is
/// configured, and returns the absolute file path.
///
/// Returns `null` when [screenshotsDirectory] is omitted and
/// [screenshotsDirEnvKey] is unset or empty.
///
/// Names start with a UTC timestamp so lexicographic order matches capture
/// time; [suffix] (e.g. `flutter`, `native`) comes after the stamp so
/// successive captures do not overwrite each other.
File? saveScreenshotPng(
  String pngBase64, {
  String suffix = 'screenshot',
  Directory? screenshotsDirectory,
  DateTime? clock,
  Map<String, String>? environment,
}) {
  final dir = screenshotsDirectory ??
      _resolveScreenshotsDirectory(environment: environment);
  if (dir == null) {
    return null;
  }

  final bytes = base64Decode(pngBase64);
  dir.createSync(recursive: true);

  final stamp = (clock ?? DateTime.now()).toUtc();
  final name = '${stamp.toIso8601String().replaceAll(':', '-')}_$suffix.png';
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file;
}

/// Returns `null` unless [screenshotsDirEnvKey] is set to a non-empty path.
Directory? _resolveScreenshotsDirectory({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final override = env[screenshotsDirEnvKey];
  if (override == null || override.trim().isEmpty) {
    return null;
  }
  return Directory(override);
}

/// Builds MCP tool content that embeds the image for the agent.
///
/// When [savedFile] is non-null, also includes the on-disk path so hosts and
/// users can open / preview the PNG.
List<Content> screenshotToolContent({
  required String pngBase64,
  File? savedFile,
}) {
  final content = <Content>[];
  if (savedFile != null) {
    final path = savedFile.absolute.path;
    content.add(
      TextContent(
        text: 'Screenshot saved to $path\n'
            'Embed this PNG for the user with markdown: ![]($path)',
      ),
    );
  }
  content.add(ImageContent(data: pngBase64, mimeType: 'image/png'));
  return content;
}
