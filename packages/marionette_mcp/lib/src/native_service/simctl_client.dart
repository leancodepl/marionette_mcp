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

  /// Grants, revokes or resets privacy [service] (e.g. `camera`, `photos`,
  /// `all`) for [bundleId] on simulator [udid] (`simctl privacy`). Changing
  /// a permission may terminate the app.
  Future<void> privacy(
    String udid,
    String action,
    String service,
    String bundleId,
  ) =>
      _simctl(['privacy', udid, action, service, bundleId]);

  /// Opens [url] on simulator [udid] (`simctl openurl`).
  Future<void> openUrl(String udid, String url) =>
      _simctl(['openurl', udid, url]);

  /// Sends the push notification payload in [payloadFile] to [bundleId]
  /// (`simctl push`).
  Future<void> push(String udid, String bundleId, String payloadFile) =>
      _simctl(['push', udid, bundleId, payloadFile]);

  /// Sets the simulated location of simulator [udid].
  Future<void> setLocation(String udid, double latitude, double longitude) =>
      _simctl(['location', udid, 'set', '$latitude,$longitude']);

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

  /// Name and OS runtime of simulator [udid], or null when it is not
  /// listed.
  Future<({String name, String runtime})?> deviceInfo(String udid) async {
    final arguments = ['simctl', 'list', 'devices', '-j'];
    final result = await _run('xcrun', arguments);
    checkProcessResult(result, 'xcrun', arguments);
    return parseSimulatorInfo(processStdout(result), udid);
  }

  /// Posts Darwin notification [name] inside simulator [udid]
  /// (`notifyutil -p`), optionally setting its state first (`-s`).
  Future<void> notify(String udid, String name, {int? state}) async {
    if (state != null) {
      await _simctl(['spawn', udid, 'notifyutil', '-s', name, '$state']);
    }
    await _simctl(['spawn', udid, 'notifyutil', '-p', name]);
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

/// Name and runtime (e.g. `iOS 18.6`) of simulator [udid] from
/// `simctl list devices -j` output.
({String name, String runtime})? parseSimulatorInfo(String json, String udid) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) return null;
  final devices = decoded['devices'];
  if (devices is! Map<String, dynamic>) return null;
  for (final MapEntry(key: runtime, value: entries) in devices.entries) {
    if (entries is! List) continue;
    for (final device in entries) {
      if (device is! Map<String, dynamic> || device['udid'] != udid) continue;
      return (
        name: device['name'] as String? ?? udid,
        runtime: simulatorRuntimeName(runtime),
      );
    }
  }
  return null;
}

/// `com.apple.CoreSimulator.SimRuntime.iOS-18-6` → `iOS 18.6`.
String simulatorRuntimeName(String identifier) {
  final last = identifier.split('.').last;
  final dash = last.indexOf('-');
  if (dash == -1) return last;
  return '${last.substring(0, dash)} '
      '${last.substring(dash + 1).replaceAll('-', '.')}';
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
