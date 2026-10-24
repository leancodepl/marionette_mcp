import 'dart:io';

import 'package:test/test.dart';

void main() {
  final lib = Directory('lib').absolute;
  final protocolRoot = lib.uri.resolve('src/mcp/');
  const compatibilityExports = {
    'src/mcp_server_runner.dart',
    'src/session/step_logger.dart',
    'src/vm_service/dynamic_extension_tools.dart',
    'src/vm_service/tools/ancestor_keys_description.dart',
    'src/vm_service/tools/tool_runner.dart',
  };

  test('lib exposes explicit entrypoints with implementation under src', () {
    final entrypoints = lib
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.uri.pathSegments.last);
    expect(
        entrypoints, unorderedEquals(['marionette_mcp.dart', 'runtime.dart']));
    expect(Directory.fromUri(lib.uri.resolve('mcp/')).existsSync(), isFalse);
    expect(Directory.fromUri(protocolRoot).existsSync(), isTrue);
  });

  test('runtime code has no MCP dependency or dependency on legacy bridges',
      () {
    final directives = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    for (final file in Directory.fromUri(lib.uri.resolve('src/'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final relative = file.absolute.uri.path.substring(lib.uri.path.length);
      final source = file.readAsStringSync();
      if (compatibilityExports.contains(relative)) {
        // Existing consumers can keep their import paths, but these bridges
        // must never become a second implementation or a runtime dependency.
        final lines = source
            .replaceAll(RegExp(r'//[^\n]*'), '')
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty);
        expect(lines, isNotEmpty, reason: relative);
        expect(
            lines.every(
                (line) => line.startsWith('export ') && line.endsWith(';')),
            isTrue,
            reason: '$relative must contain exports only');
        continue;
      }
      if (file.absolute.uri.path.startsWith(protocolRoot.path)) continue;
      for (final directive in directives.allMatches(source)) {
        final imported = directive.group(1)!;
        expect(imported.startsWith('package:mcp_dart/'), isFalse,
            reason: '$relative must stay independent of the MCP SDK');
        final Uri target;
        if (imported.startsWith('package:marionette_mcp/')) {
          target = lib.uri
              .resolve(imported.substring('package:marionette_mcp/'.length));
        } else if (!Uri.parse(imported).hasScheme) {
          target = file.absolute.uri.resolve(imported);
        } else {
          continue;
        }
        expect(target.path.startsWith(protocolRoot.path), isFalse,
            reason: '$relative must not depend on MCP adapters');
        for (final bridge in compatibilityExports) {
          expect(target, isNot(lib.uri.resolve(bridge)),
              reason: '$relative must import runtime APIs directly');
        }
      }
    }
  });
}
