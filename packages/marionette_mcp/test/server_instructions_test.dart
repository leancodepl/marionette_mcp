import 'package:marionette_mcp/src/mcp_server_runner.dart';
import 'package:test/test.dart';

void main() {
  test('server instructions fit the 4096 characters Claude Code keeps', () {
    // Longer instructions were cut off mid-way through the native lane
    // section, so agents never saw its rules.
    expect(serverInstructions.length, lessThanOrEqualTo(4096));
  });

  test('server instructions keep the native lane rules', () {
    for (final rule in [
      'native_get_elements',
      'native_connect before the flow opens system UI',
      'native_wait_for',
      'screen pixels',
      'reset the permission outside Marionette',
    ]) {
      expect(serverInstructions, contains(rule), reason: rule);
    }
  });
}
