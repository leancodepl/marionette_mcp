import 'dart:io';

import 'package:marionette_cli/src/cli/commands/doctor_command.dart';
import 'package:marionette_cli/src/cli/instance_command.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class ElementsCommand extends InstanceCommand {
  ElementsCommand(this._registry) {
    argParser.addMultiOption('ancestor-keys', help: _ancestorKeysHelp);
    argParser.addOption(
      'compaction',
      help: 'How much to reduce the payload. "compact" drops icon-font '
          'glyphs, rendering details and font metrics, rounds bounds to '
          'whole pixels, and reports visible only when false. "none" forces '
          "the full payload. Omit to use the app's configured default.",
      allowed: supportedCompactionModes.toList(),
    );
  }

  final InstanceRegistry _registry;

  @override
  InstanceRegistry get registry => _registry;

  @override
  String get name => 'get-interactive-elements';

  @override
  String get description =>
      'List interactive elements in the Flutter app UI tree.';

  @override
  Future<int> execute(VmServiceConnector connector) async {
    final compaction = argResults?['compaction'] as String?;
    final response = await connector.getInteractiveElements(
      ancestorKeys: argResults?['ancestor-keys'] as List<String>? ?? const [],
      compaction: compaction,
    );
    final elements = response['elements'] as List<dynamic>;

    final warning = coveredAppWarning(
      response,
      nativeElements: 'marionette native-get-elements',
    );
    if (warning != null) stdout.writeln('$warning\n');
    stdout.writeln('Found ${elements.length} interactive element(s):\n');

    for (final element in elements) {
      stdout.writeln(formatElement(element as Map<String, dynamic>));
    }

    await _warnAboutUiSupport(connector);
    return 0;
  }

  /// Writes a warning to stderr, keeping stdout to the listing, when the
  /// app's UI integrations need a look. Without a source-confirmed scope it
  /// can only point at loaded libraries that have no integration.
  Future<void> _warnAboutUiSupport(VmServiceConnector connector) async {
    try {
      final report = await connector.inspectUiSupport();
      final warning =
          uiSupportWarning(report, scopeHint: doctorScopeHint('<instance>'));
      if (warning != null) stderr.writeln(warning);
    } catch (e) {
      stderr.writeln('Warning: could not check UI integrations: $e');
    }
  }
}

/// Help text for `--ancestor-keys` on `get-interactive-elements`, which lists a
/// subtree rather than matching one element inside it.
const _ancestorKeysHelp = 'List only the elements inside the subtree of the '
    'element with this key. Use it to cut the output down on screens that '
    'repeat the same subtree (grid cells, repeated cards). Repeat the option, '
    "outermost wrapper first, to go deeper: each key is looked up inside the "
    "previous one's subtree.";
