import 'package:marionette_flutter/src/services/log_collector.dart';

/// A generic [LogCollector] that can be used with any logging solution.
///
/// This collector exposes an [addLog] method that can be called from your
/// logging listener to forward logs to the Marionette system.
///
/// ## Example with the `logging` package
///
/// ```dart
/// final collector = PrintLogCollector();
/// MarionetteBinding.ensureInitialized(
///   MarionetteConfiguration(logCollector: collector),
/// );
///
/// Logger.root.level = Level.ALL;
/// Logger.root.onRecord.listen((record) {
///   collector.addLog('${record.level.name}: ${record.loggerName}: ${record.message}');
/// });
/// ```
///
/// ## Example with Zone to capture print statements
///
/// ```dart
/// final collector = PrintLogCollector();
/// MarionetteBinding.ensureInitialized(
///   MarionetteConfiguration(logCollector: collector),
/// );
///
/// runZoned(
///   () => runApp(MyApp()),
///   zoneSpecification: ZoneSpecification(
///     print: (self, parent, zone, line) {
///       parent.print(zone, line);
///       collector.addLog(line);
///     },
///   ),
/// );
/// ```
class PrintLogCollector implements LogCollector {
  void Function(String)? _onLog;

  @override
  void start(void Function(String log) onLog) {
    _onLog = onLog;
  }

  /// Adds a log entry.
  ///
  /// Call this method from your logging listener to forward logs to the
  /// Marionette system. The message is stored as-is - formatting is the
  /// caller's responsibility.
  void addLog(String message) {
    _onLog?.call(message);
  }

  @override
  void dispose() {
    _onLog = null;
  }
}
