import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_mcp/marionette_mcp.dart';

import '../instance_registry.dart';

/// Base class for commands that operate on a connected Flutter app instance.
///
/// Handles resolving the instance name from the global `--instance` flag,
/// looking up the URI from the registry, connecting, executing, and
/// disconnecting.
abstract class InstanceCommand extends Command<int> {
  InstanceRegistry get registry;

  /// Subclasses implement this to perform their operation on a connected
  /// [connector].
  Future<int> execute(VmServiceConnector connector);

  @override
  Future<int> run() async {
    final instanceName = globalResults?['instance'] as String?;
    if (instanceName == null || instanceName.isEmpty) {
      usageException('--instance (-i) is required for this command.');
    }

    final info = registry.get(instanceName);
    if (info == null) {
      stderr.writeln(
        'Instance "$instanceName" not found. '
        'Use "marionette list" to see registered instances.',
      );
      return 1;
    }

    final timeoutSeconds =
        int.parse(globalResults?['timeout'] as String? ?? '5');
    final connector = VmServiceConnector();

    try {
      await connector.connect(info.uri).timeout(
            Duration(seconds: timeoutSeconds),
            onTimeout: () => throw TimeoutException(
              'Connection to "${info.name}" at ${info.uri} timed out '
              'after ${timeoutSeconds}s. Is the app still running?',
            ),
          );
      return await execute(connector);
    } on SocketException catch (e) {
      stderr.writeln(
        'Could not connect to "$instanceName" at ${info.uri}: $e\n'
        'The app may have stopped. '
        'Try "marionette doctor" or "marionette unregister $instanceName".',
      );
      return 1;
    } on TimeoutException catch (e) {
      stderr.writeln(e.message);
      return 1;
    } catch (e) {
      stderr.writeln('Error: $e');
      return 1;
    } finally {
      await connector.disconnect();
    }
  }
}

class TimeoutException implements Exception {
  TimeoutException(this.message);
  final String message;

  @override
  String toString() => message;
}
