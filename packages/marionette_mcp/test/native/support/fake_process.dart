import 'dart:async';
import 'dart:io';

/// A started process whose output and exit the test controls.
class FakeProcess implements Process {
  /// [pid] stays above every host's pid limit, so a `Process.killPid` on it
  /// reaches no process.
  FakeProcess({this.pid = 1 << 30});

  @override
  final int pid;

  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  final _exitCode = Completer<int>();

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  /// Ends the process with [code].
  void exit(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    exit(-signal.signalNumber);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
