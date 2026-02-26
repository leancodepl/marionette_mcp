import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand(this._registry);

  final InstanceRegistry _registry;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check connectivity of all registered Flutter app instances.';

  @override
  Future<int> run() async {
    final instances = _registry.listAll();

    if (instances.isEmpty) {
      stdout.writeln('No instances registered.');
      return 0;
    }

    final timeoutSeconds = int.parse(
      globalResults?['timeout'] as String? ?? '5',
    );
    var allHealthy = true;

    stdout.writeln('Checking ${instances.length} instance(s)...\n');

    for (final info in instances) {
      stdout.write('  ${info.name} (${info.uri}) ... ');
      final connector = VmServiceConnector();

      try {
        await connector
            .connect(info.uri)
            .timeout(Duration(seconds: timeoutSeconds));
        stdout.writeln('OK');
      } catch (e) {
        stdout.writeln('FAILED');
        stderr.writeln('    $e');
        allHealthy = false;
      } finally {
        try {
          await connector.disconnect();
        } catch (_) {}
      }
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
}
