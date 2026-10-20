import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/cli/native_doctor.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand(this._registry, this._nativeDoctor);

  final InstanceRegistry _registry;
  final NativeDoctor _nativeDoctor;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check connectivity of all registered Flutter app instances and the '
      'native lane setup (devices, servers, native sessions).';

  @override
  Future<int> run() async {
    final instancesHealthy = await _checkInstances();
    final nativeHealthy = await _checkNativeLane();
    return instancesHealthy && nativeHealthy ? 0 : 1;
  }

  Future<bool> _checkNativeLane() async {
    stdout.writeln('\nNative lane:');
    var healthy = true;
    for (final finding in await _nativeDoctor.check()) {
      final mark = switch (finding.status) {
        DoctorStatus.ok => '✓',
        DoctorStatus.note => '!',
        DoctorStatus.problem => '✗',
      };
      stdout.writeln('  $mark ${finding.message}');
      if (finding.fix case final fix?) stdout.writeln('      Fix: $fix');
      if (finding.status == DoctorStatus.problem) healthy = false;
    }
    return healthy;
  }

  Future<bool> _checkInstances() async {
    final instances = _registry.listAll();

    if (instances.isEmpty) {
      stdout.writeln('No instances registered.');
      return true;
    }

    final rawTimeout = globalResults?['timeout'] as String? ?? '5';
    final timeoutSeconds = int.tryParse(rawTimeout);
    if (timeoutSeconds == null) {
      usageException('Invalid timeout value: "$rawTimeout"');
    }
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

    return allHealthy;
  }
}
