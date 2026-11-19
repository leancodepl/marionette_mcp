/// Checks [condition] up to [attempts] times, [interval] apart; returns true
/// as soon as it holds, false right after the last check (at
/// ([attempts] - 1) × [interval]).
Future<bool> pollUntil(
  Future<bool> Function() condition, {
  required int attempts,
  required Duration interval,
}) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    if (await condition()) return true;
    if (attempt < attempts) await Future<void>.delayed(interval);
  }
  return false;
}
