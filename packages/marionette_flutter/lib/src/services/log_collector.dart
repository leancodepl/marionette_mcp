import 'dart:collection';

import 'package:logging/logging.dart';

/// Collects and stores Flutter logs for retrieval via VM service extension.
class LogCollector {
  final _logs = Queue<String>();
  static const _maxLogs = 1000;
  bool _initialized = false;

  /// Initializes the log collector to start capturing logs.
  void initialize() {
    if (_initialized) {
      return;
    }

    Logger.root.onRecord.listen((record) {
      _logs.add(_formatLogRecord(record));

      // Keep only the most recent logs
      if (_logs.length > _maxLogs) {
        _logs.removeFirst();
      }
    });

    _initialized = true;
  }

  /// Returns all collected logs as a list of formatted strings.
  List<String> getFormattedLogs() {
    return _logs.toList();
  }

  /// Returns all collected logs as a single formatted text string.
  String getFormattedLogsAsText() {
    return _logs.join('\n');
  }

  /// Clears all collected logs.
  void clear() {
    _logs.clear();
  }

  /// Returns the number of collected logs.
  int get count => _logs.length;

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
