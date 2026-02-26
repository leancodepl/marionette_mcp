import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:marionette_cli/src/instance_registry.dart';
import 'package:marionette_mcp/src/vm_service/vm_service_connector.dart';

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
    final rawInstance = globalResults?['instance'] as String?;
    final rawUri = globalResults?['uri'] as String?;
    final instanceName = (rawInstance != null && rawInstance.isNotEmpty)
        ? rawInstance
        : null;
    final directUri = (rawUri != null && rawUri.isNotEmpty) ? rawUri : null;

    if (instanceName != null && directUri != null) {
      usageException(
        '--instance (-i) and --uri are mutually exclusive. Use one or the other.',
      );
    }

    if (instanceName == null && directUri == null) {
      usageException('--instance (-i) or --uri is required for this command.');
    }

    late final String uri;
    late final String displayName;
    final isStateless = directUri != null;

    if (directUri != null) {
      uri = directUri;
      displayName = directUri;
    } else if (instanceName != null) {
      final info = registry.get(instanceName);
      if (info == null) {
        stderr.writeln(
          'Instance "$instanceName" not found. '
          'Use "marionette list" to see registered instances.',
        );
        return 1;
      }
      uri = info.uri;
      displayName = instanceName;
    }

    final timeoutSeconds = int.parse(
      globalResults?['timeout'] as String? ?? '5',
    );
    final connector = VmServiceConnector();

    try {
      await connector
          .connect(uri)
          .timeout(
            Duration(seconds: timeoutSeconds),
            onTimeout: () => throw TimeoutException(
              'Connection to "$displayName" at $uri timed out '
              'after ${timeoutSeconds}s. Is the app still running?',
            ),
          );
      return await execute(connector);
    } on SocketException catch (e) {
      final hint = isStateless
          ? 'Check the URI and ensure the app is still running.'
          : 'The app may have stopped. '
                'Try "marionette doctor" or "marionette unregister $displayName".';
      stderr.writeln('Could not connect to "$displayName" at $uri: $e\n$hint');
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
