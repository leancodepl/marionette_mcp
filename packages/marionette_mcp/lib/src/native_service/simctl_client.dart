import 'dart:convert';
import 'dart:io';

import 'package:marionette_mcp/src/native_service/process.dart';

/// Thin wrapper over `xcrun simctl` for iOS Simulator management.
class SimctlClient {
  SimctlClient({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  /// UDIDs of all booted simulators, in `simctl` listing order.
  ///
  /// Throws [ProcessCommandException] when `simctl` fails and
  /// [FormatException] when its JSON output is not in the expected shape.
  Future<List<String>> listBootedUdids() async {
    final arguments = ['simctl', 'list', 'devices', 'booted', '-j'];
    final result = await _run('xcrun', arguments);
    checkProcessResult(result, 'xcrun', arguments);
    return parseBootedUdids(processStdout(result));
  }

  /// Installs the app bundle at [bundlePath] on simulator [udid].
  Future<void> install(String udid, String bundlePath) =>
      _simctl(['install', udid, bundlePath]);

  /// Launches [bundleId] on simulator [udid].
  Future<void> launch(String udid, String bundleId) =>
      _simctl(['launch', udid, bundleId]);

  /// Terminates [bundleId] on simulator [udid].
  Future<void> terminate(String udid, String bundleId) =>
      _simctl(['terminate', udid, bundleId]);

  /// Whether [bundleId] has a running process on simulator [udid], read from
  /// `launchctl list` inside the simulator. Null when it cannot be read.
  Future<bool?> isAppRunning(String udid, String bundleId) async {
    try {
      final result =
          await _run('xcrun', ['simctl', 'spawn', udid, 'launchctl', 'list']);
      if (result.exitCode != 0) return null;
      return parseLaunchctlAppRunning(processStdout(result), bundleId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _simctl(List<String> arguments) async {
    final fullArguments = ['simctl', ...arguments];
    final result = await _run('xcrun', fullArguments);
    checkProcessResult(result, 'xcrun', fullArguments);
  }
}

/// Whether `launchctl list` output has a running process (numeric pid) for
/// [bundleId] (label `UIKitApplication:<bundleId>[...]`).
bool parseLaunchctlAppRunning(String output, String bundleId) {
  final label = 'UIKitApplication:$bundleId[';
  for (final line in output.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 3 || !parts[2].startsWith(label)) continue;
    if (int.tryParse(parts[0]) != null) return true;
  }
  return false;
}

/// Parses `xcrun simctl list devices booted -j` output into booted UDIDs.
List<String> parseBootedUdids(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Unexpected simctl JSON: expected an object');
  }
  final devices = decoded['devices'];
  if (devices is! Map<String, dynamic>) {
    throw const FormatException('Unexpected simctl JSON: missing devices map');
  }

  final booted = <String>[];
  for (final entry in devices.values) {
    if (entry is! List) continue;
    for (final device in entry) {
      if (device is! Map<String, dynamic>) continue;
      final state = device['state'] as String?;
      final udid = device['udid'] as String?;
      if (state == 'Booted' && udid != null && udid.isNotEmpty) {
        booted.add(udid);
      }
    }
  }
  return booted;
}
