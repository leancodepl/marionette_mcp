import 'dart:async';

import 'package:logging/logging.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

/// A [LogCollector] that automatically subscribes to [Logger.root.onRecord]
/// and provides rich formatting including level, logger name, errors, and
/// stack traces.
///
/// ## Example
///
/// ```dart
/// import 'package:marionette_logging/marionette_logging.dart';
///
/// void main() {
///   MarionetteBinding.ensureInitialized(
///     MarionetteConfiguration(logCollector: LoggingLogCollector()),
///   );
///   Logger.root.level = Level.ALL;
///   runApp(const MyApp());
/// }
/// ```
class LoggingLogCollector implements LogCollector {
  StreamSubscription<LogRecord>? _subscription;

  @override
  void start(void Function(String log) onLog) {
    _subscription?.cancel();
    _subscription = Logger.root.onRecord.listen((record) {
      onLog(_formatLogRecord(record));
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  String _formatLogRecord(LogRecord record) {
    final buffer = StringBuffer()
      ..write('[')
      ..write(_formatTime(record.time))
      ..write('][')
      ..write(record.level.name.toUpperCase())
      ..write('][')
      ..write(record.loggerName)
      ..write('] ')
      ..write(record.message);

    if (record.error != null) {
      buffer.write('\n  Error: ${record.error}');
    }

    if (record.stackTrace != null) {
      buffer.write('\n  Stack trace:\n');
      final stackLines = record.stackTrace.toString().split('\n');
      for (final line in stackLines) {
        if (line.isNotEmpty) {
          buffer.write('    $line\n');
        }
      }
    }

    return buffer.toString();
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
