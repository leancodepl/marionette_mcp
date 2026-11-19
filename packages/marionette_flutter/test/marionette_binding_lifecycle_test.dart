import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:marionette_flutter/src/services/log_collector.dart';
import 'package:marionette_flutter/src/services/screencast_server.dart';

void main() {
  test('reassemble clears logs, awaits screencast cleanup, and chains',
      () async {
    final collector = _RecordingLogCollector();
    final server = _DelayedScreencastServer();
    final binding = _LifecycleBinding(
      MarionetteConfiguration(logCollector: collector),
      server,
    );
    collector.emit('before reload');

    final reassemble = binding.performReassemble();
    expect(binding.logStore, isNotNull);
    expect(binding.logStore!.getLogs(), isEmpty);
    expect(binding.superReassembleCalled, isFalse);

    await Future<void>.delayed(Duration.zero);
    expect(binding.superReassembleCalled, isFalse);

    server.completeStop();
    await reassemble;
    expect(binding.superReassembleCalled, isTrue);
  });
}

class _LifecycleBinding extends WidgetsFlutterBinding
    with _ReassembleObserver, MarionetteBindingMixin {
  _LifecycleBinding(this._configuration, this.server);

  final MarionetteConfiguration _configuration;
  final _DelayedScreencastServer server;

  @override
  MarionetteConfiguration get configuration => _configuration;

  @override
  ScreencastServer get screencastServer => server;
}

mixin _ReassembleObserver on WidgetsBinding {
  var superReassembleCalled = false;

  @override
  Future<void> performReassemble() async {
    superReassembleCalled = true;
    await super.performReassemble();
  }
}

class _RecordingLogCollector implements LogCollector {
  late void Function(String) _addLog;

  @override
  void start(void Function(String) addLog) => _addLog = addLog;

  @override
  void dispose() {}

  void emit(String log) => _addLog(log);
}

class _DelayedScreencastServer implements ScreencastServer {
  final _stop = Completer<void>();

  @override
  bool get isActive => true;

  @override
  Future<Map<String, dynamic>> startScreencast({
    int? maxWidth,
    int? maxHeight,
    int? wsPort,
  }) async =>
      {};

  @override
  Future<void> stopScreencast() => _stop.future;

  void completeStop() => _stop.complete();
}
