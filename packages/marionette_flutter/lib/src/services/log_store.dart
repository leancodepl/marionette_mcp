import 'dart:collection';

/// Stores collected logs in memory with a maximum capacity.
///
/// This class is used internally by [MarionetteBinding] to store logs
/// received from a [LogCollector].
class LogStore {
  final _logs = Queue<String>();

  /// Maximum number of logs to store. Older logs are discarded when exceeded.
  static const maxLogs = 1000;

  /// Adds a log entry to the store.
  ///
  /// If the store is at capacity, the oldest log entry is removed.
  void add(String log) {
    _logs.add(log);

    // Keep only the most recent logs
    if (_logs.length > maxLogs) {
      _logs.removeFirst();
    }
  }

  /// Returns all collected logs as a list of strings.
  List<String> getLogs() {
    return _logs.toList();
  }

  /// Clears all collected logs.
  void clear() {
    _logs.clear();
  }

  /// Returns the number of collected logs.
  int get count => _logs.length;
}
