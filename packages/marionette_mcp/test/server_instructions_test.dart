import 'package:marionette_mcp/src/mcp_server_runner.dart';
import 'package:test/test.dart';

void main() {
  test('server instructions fit the 4096 characters Claude Code keeps', () {
    // Longer instructions were cut off mid-way through the native lane
    // section, so agents never saw its rules.
    expect(
      serverInstructions(enableNativeLane: true).length,
      lessThanOrEqualTo(4096),
    );
  });

  test('without the native lane, the instructions name no native tool', () {
    expect(
      serverInstructions(enableNativeLane: false),
      allOf(isNot(contains('Native lane')), isNot(contains('native_'))),
    );
  });
}
