import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Collects every record logged from now until the end of the current test.
List<LogRecord> captureLogRecords() {
  final records = <LogRecord>[];
  final subscription = Logger.root.onRecord.listen(records.add);
  addTearDown(subscription.cancel);
  return records;
}
