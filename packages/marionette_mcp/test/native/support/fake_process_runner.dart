import 'dart:io';

/// A command run through [FakeProcessRunner].
typedef ProcessCall = ({String executable, List<String> arguments});

/// Scripted `ProcessRunner` for tests.
///
/// Responses are matched by executable and argument prefix; the most recently
/// registered match wins, so tests can override defaults. `adb -s <serial>`
/// prefixes are ignored when matching [onAdb] rules. Unmatched commands
/// succeed with empty output.
class FakeProcessRunner {
  final List<ProcessCall> calls = [];
  final List<_Rule> _rules = [];

  /// Responds to `executable argsPrefix...` with [result] (or the result of
  /// [respond]); [error] makes the call throw instead.
  void on(
    String executable,
    List<String> argsPrefix, {
    ProcessResult? result,
    ProcessResult Function(List<String> arguments)? respond,
    Object? error,
  }) {
    _rules.add(
      _Rule(
        executable,
        argsPrefix,
        respond ?? (_) => result ?? ok(),
        error,
        ignoreSerial: false,
      ),
    );
  }

  /// Like [on] for `adb`, ignoring a leading `-s <serial>`.
  void onAdb(
    List<String> commandPrefix, {
    ProcessResult? result,
    ProcessResult Function(List<String> arguments)? respond,
    Object? error,
  }) {
    _rules.add(
      _Rule(
        'adb',
        commandPrefix,
        respond ?? (_) => result ?? ok(),
        error,
        ignoreSerial: true,
      ),
    );
  }

  /// Makes every call to [executable] throw [error] (e.g. not on PATH).
  void failExecutable(String executable, Object error) =>
      on(executable, const [], error: error);

  /// `adb` commands received, without the `-s <serial>` prefix.
  List<List<String>> get adbCommands => calls
      .where((call) => call.executable == 'adb')
      .map((call) => stripSerial(call.arguments))
      .toList();

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: List.of(arguments)));
    for (final rule in _rules.reversed) {
      if (!rule.matches(executable, arguments)) continue;
      final error = rule.error;
      if (error != null) throw error;
      return rule.respond(arguments);
    }
    return ok();
  }
}

/// Successful process result with [stdout].
ProcessResult ok([String stdout = '']) => ProcessResult(0, 0, stdout, '');

/// Failed process result.
ProcessResult failed(
        {int exitCode = 1, String stderr = '', String stdout = ''}) =>
    ProcessResult(0, exitCode, stdout, stderr);

/// Drops a leading `-s <serial>` from adb arguments.
List<String> stripSerial(List<String> arguments) =>
    arguments.length >= 2 && arguments[0] == '-s'
        ? arguments.sublist(2)
        : arguments;

class _Rule {
  _Rule(
    this.executable,
    this.prefix,
    this.respond,
    this.error, {
    required this.ignoreSerial,
  });

  final String executable;
  final List<String> prefix;
  final ProcessResult Function(List<String> arguments) respond;
  final Object? error;
  final bool ignoreSerial;

  bool matches(String executable, List<String> arguments) {
    if (executable != this.executable) return false;
    final args = ignoreSerial ? stripSerial(arguments) : arguments;
    if (args.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (args[i] != prefix[i]) return false;
    }
    return true;
  }
}
