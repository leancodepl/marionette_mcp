import 'package:logging/logging.dart' as logging;
import 'package:marionette_mcp/src/mcp_server_runner.dart';
import 'package:test/test.dart';

void main() {
  test('a log line includes the error of a failed tool call', () {
    // The server log of a failed tool call said only "Failed to native
    // wait for", without the reason.
    final record = logging.LogRecord(
      logging.Level.WARNING,
      'Failed to native wait for',
      'NativeServiceContext',
      StateError('Application is not running'),
    );

    expect(
      formatLogRecord(record),
      allOf(
        startsWith('[WARNING][NativeServiceContext]['),
        endsWith('] Failed to native wait for: '
            'Bad state: Application is not running'),
      ),
    );
  });

  test('a log line without an error is just the message', () {
    final record =
        logging.LogRecord(logging.Level.INFO, 'Native app activate', 'X');

    expect(formatLogRecord(record), endsWith('] Native app activate'));
  });
}
