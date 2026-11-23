import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/formatting.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_library.dart';
import 'package:marionette_mcp/src/vm_service/ui_support_state.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

/// How `doctor` takes the UI libraries a source preflight confirmed for
/// [instance], for the UI integration status.
String doctorScopeHint(String instance) =>
    'run "marionette -i $instance doctor --required-ui-library <name>" for '
    'each of them';

class DoctorCommand extends Command<int> {
  DoctorCommand(this._registry) {
    argParser.addMultiOption(
      'required-ui-library',
      help: "An extracted UI library the app's active entrypoint imports in "
          'its source; a library only a dependency loads needs no '
          'integration. Repeat it for each library. Needs --instance, and '
          "doctor then reports whether that app's configuration covers them.",
      allowed: [
        for (final library in UiSupportLibrary.values) library.wireName
      ],
    );
  }

  final InstanceRegistry _registry;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check connectivity and UI integrations of all registered Flutter app '
      'instances, or of the one --instance names.';

  @override
  Future<int> run() async {
    final rawInstance = globalResults?['instance'] as String?;
    final instanceName =
        (rawInstance != null && rawInstance.isNotEmpty) ? rawInstance : null;
    final requiredNames = argResults!['required-ui-library'] as List<String>;
    if (requiredNames.isNotEmpty && instanceName == null) {
      usageException(
        '--required-ui-library needs --instance (-i) to name the app whose '
        'source you checked.',
      );
    }

    final rawTimeout = globalResults?['timeout'] as String? ?? '5';
    final timeoutSeconds = int.tryParse(rawTimeout);
    if (timeoutSeconds == null) {
      stderr.writeln('Invalid timeout value: "$rawTimeout"');
      return 64;
    }
    final timeout = Duration(seconds: timeoutSeconds);

    if (instanceName != null) {
      final info = _registry.get(instanceName) ??
          usageException(
            'Instance "$instanceName" not found. '
            'Use "marionette list" to see registered instances.',
          );
      final requiredLibraries = requiredNames.isEmpty
          ? null
          : UiSupportLibrary.parseAll(requiredNames);
      stdout.writeln('Checking instance ${info.name}...\n');
      return await _check(info, timeout, requiredLibraries) ? 0 : 1;
    }

    final instances = _registry.listAll();

    if (instances.isEmpty) {
      stdout.writeln('No instances registered.');
      return 0;
    }

    var allHealthy = true;

    stdout.writeln('Checking ${instances.length} instance(s)...\n');

    for (final info in instances) {
      if (!await _check(info, timeout, null)) allHealthy = false;
    }

    stdout.writeln();
    if (allHealthy) {
      stdout.writeln('All instances are reachable.');
    } else {
      stdout.writeln(
        'Some instances are unreachable. '
        'Use "marionette unregister --stale" to remove them.',
      );
    }

    return allHealthy ? 0 : 1;
  }

  /// Connects to [info] and prints whether it is reachable and its UI
  /// integrations against [requiredLibraries].
  ///
  /// Returns false when the app is unreachable or misses a required
  /// integration, and when the UI integration check fails for a given
  /// [requiredLibraries]. Without them a failed check is printed but leaves
  /// the result to connectivity.
  Future<bool> _check(
    InstanceInfo info,
    Duration timeout,
    Set<UiSupportLibrary>? requiredLibraries,
  ) async {
    stdout.write('  ${info.name} (${info.uri}) ... ');
    final connector = VmServiceConnector();

    try {
      await connector.connect(info.uri, timeout: timeout);
      stdout.writeln('OK');
      try {
        final report = await connector
            .inspectUiSupport(requiredLibraries: requiredLibraries)
            .timeout(timeout);
        final status =
            describeUiSupport(report, scopeHint: doctorScopeHint(info.name));
        stdout.writeln('    $status');
        return report.state != UiSupportState.missing;
      } catch (e) {
        stderr.writeln('    UI integrations: could not be checked: $e');
        return requiredLibraries == null;
      }
    } catch (e) {
      stdout.writeln('FAILED');
      stderr.writeln('    $e');
      return false;
    } finally {
      try {
        await connector.disconnect();
      } catch (_) {}
    }
  }
}
